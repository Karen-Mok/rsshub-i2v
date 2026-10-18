import { load } from 'cheerio';

import type { DataItem, Route } from '@/types';
import cache from '@/utils/cache';
import got from '@/utils/got';
import { parseDate } from '@/utils/parse-date';
import timezone from '@/utils/timezone';

const rootUrl = 'http://www.ctaweb.org.cn';

export const route: Route = {
    path: '/',
    categories: ['study'],
    example: '/ctaweb',
    parameters: {},
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
            source: ['www.ctaweb.org.cn'],
            target: '/',
        },
    ],
    name: '工作动态与通知公告',
    maintainers: ['karenmok'],
    handler,
    url: 'www.ctaweb.org.cn',
    description: '中国旅游研究院（文化和旅游部数据中心）官网首页。假日旅游市场数据、季度趋势报告发布处。',
};

async function handler(ctx) {
    const limit = ctx.req.query('limit') ? Number(ctx.req.query('limit')) : 15;
    const currentUrl = `${rootUrl}/`;

    const { data: response } = await got(currentUrl);
    const $ = load(response);

    const list = $('a[href^="/gongzuodongtai/"], a[href^="/tongzhigonggao/"]')
        .toArray()
        .map((item) => {
            const $item = $(item);
            const href = $item.prop('href');
            if (!href) {
                return null;
            }
            const link = new URL(href, rootUrl).href;
            const title = $item.text().trim();
            if (!title) {
                return null;
            }
            return { title, link } as DataItem;
        })
        .filter(Boolean) as DataItem[];

    const seen = new Set<string>();
    const uniq = list.filter((item) => {
        if (seen.has(item.link!)) {
            return false;
        }
        seen.add(item.link!);
        return true;
    }).slice(0, limit);

    const items = await Promise.all(
        uniq.map((item) =>
            cache.tryGet(item.link!, async () => {
                try {
                    const { data: detail } = await got(item.link);
                    const $$ = load(detail);
                    const description = $$('#zoom').html() || $$('.details').html();
                    if (description) {
                        item.description = description;
                        item.content = { html: description, text: ($$('#zoom').text() || $$('.details').text()).trim() };
                    }
                    const dateText = $$.text().match(/20\d{2}-\d{2}-\d{2}/);
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
        title: '中国旅游研究院-工作动态与通知公告',
        link: currentUrl,
        item: items,
        allowEmpty: true,
    };
}
