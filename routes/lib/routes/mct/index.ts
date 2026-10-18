import { load } from 'cheerio';

import type { DataItem, Route } from '@/types';
import cache from '@/utils/cache';
import got from '@/utils/got';
import { parseDate } from '@/utils/parse-date';
import timezone from '@/utils/timezone';

const rootUrl = 'https://www.mct.gov.cn';

export const route: Route = {
    path: '/:category{.+}?',
    categories: ['government'],
    example: '/mct/whzx/whyw',
    parameters: { category: '栏目路径，默认 `whzx/whyw`（文化要闻）。可在栏目页 URL 中截取，如 `https://www.mct.gov.cn/whzx/whyw/` → `whzx/whyw`' },
    features: {
        requireConfig: false,
        requirePuppeteer: false,
        antiCrawler: false,
        supportBT: false,
        supportPodcast: false,
        supportScihub: false,
    },
    radar: [
        {
            source: ['www.mct.gov.cn/:category/'],
            target: '/:category',
        },
    ],
    name: '栏目',
    maintainers: ['karenmok'],
    handler,
    url: 'www.mct.gov.cn',
    description: `文化和旅游部官网栏目。常用：\`whzx/whyw\`（文化要闻）、\`whzx/bnsj\`（部内司局动态）`,
};

async function handler(ctx) {
    const { category = 'whzx/whyw' } = ctx.req.param();
    const limit = ctx.req.query('limit') ? Number(ctx.req.query('limit')) : 15;
    const currentUrl = `${rootUrl}/${category.replace(/^\//, '').replace(/\/$/, '')}/`;

    const { data: response } = await got(currentUrl);
    const $ = load(response);

    const list = ($('a[href*="t20"][title], a[href*="t20"]')
        .toArray()
        .map((item) => {
            const $item = $(item);
            const href = $item.prop('href');
            if (!href || href === '' || href === '#') {
                return null;
            }
            const link = href.startsWith('http') ? href : new URL(href, currentUrl).href;
            const m = link.match(/t(\d{4})(\d{2})(\d{2})_/);
            const title = ($item.prop('title') || $item.text()).trim();
            if (!title) {
                return null;
            }
            return {
                title,
                link,
                pubDate: m ? parseDate(`${m[1]}-${m[2]}-${m[3]}`) : undefined,
            } as DataItem;
        })
        .filter(Boolean)
        .slice(0, limit)) as DataItem[];

    const items = await Promise.all(
        list.map((item) =>
            cache.tryGet(item.link!, async () => {
                try {
                    const { data: detail } = await got(item.link);
                    const $$ = load(detail);
                    const description = $$('#zoom').html();
                    if (description) {
                        item.description = description;
                        item.content = { html: description, text: $$('#zoom').text().trim() };
                    }
                    const dateText = $$.text().match(/20\d{2}-\d{2}-\d{2}(?:\s+\d{2}:\d{2}(?::\d{2})?)?/);
                    if (dateText) {
                        item.pubDate = timezone(parseDate(dateText[0]), +8);
                    }
                } catch {
                    // 详情页失败时保留列表页信息
                }
                return item;
            })
        )
    );

    return {
        title: $('title').text().split('-')[0]?.trim() || `文化和旅游部-${category}`,
        link: currentUrl,
        item: items,
        allowEmpty: true,
    };
}
