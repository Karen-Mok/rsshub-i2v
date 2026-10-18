import { load } from 'cheerio';

import type { DataItem, Route } from '@/types';
import cache from '@/utils/cache';
import got from '@/utils/got';
import { parseDate } from '@/utils/parse-date';
import timezone from '@/utils/timezone';

const rootUrl = 'https://www.caac.gov.cn';

// 栏目对照：路径 => 中文名
const channels = {
    MHYW: '民航要闻',
    DFDT: '地方动态',
    HYDT: '行业动态',
    MTZX: '媒体中心',
    XWFBH: '新闻发布会',
};

export const route: Route = {
    path: '/xwzx/:channel?',
    categories: ['government'],
    example: '/caac/xwzx/mhyw',
    parameters: { channel: '栏目代码，默认 `MHYW`（民航要闻）' },
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
            source: ['www.caac.gov.cn/XWZX/:channel/'],
            target: '/xwzx/:channel',
        },
    ],
    name: '新闻中心',
    maintainers: ['karenmok'],
    handler,
    url: 'www.caac.gov.cn/XWZX/',
    description: `| 栏目 | 代码 |
| ---- | ---- |
| 民航要闻 | MHYW |
| 地方动态 | DFDT |
| 行业动态 | HYDT |
| 媒体中心 | MTZX |
| 新闻发布会 | XWFBH |`,
};

async function handler(ctx) {
    const { channel = 'MHYW' } = ctx.req.param();
    const limit = ctx.req.query('limit') ? Number(ctx.req.query('limit')) : 15;
    const currentUrl = `${rootUrl}/XWZX/${channel.toUpperCase()}/`;

    const { data: response } = await got(currentUrl);
    const $ = load(response);

    const list = ($('a[href*="t20"][title]')
        .toArray()
        .map((item) => {
            const $item = $(item);
            const href = $item.prop('href');
            const link = href.startsWith('http') ? href : new URL(href, currentUrl).href;
            const m = link.match(/t(\d{4})(\d{2})(\d{2})_/);
            return {
                title: ($item.prop('title') || $item.text()).trim(),
                link,
                pubDate: m ? parseDate(`${m[1]}-${m[2]}-${m[3]}`) : undefined,
            } as DataItem;
        })
        .filter((item) => item.title && item.link)
        .slice(0, limit));

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
        title: `中国民航局-${channels[channel.toUpperCase()] ?? channel}`,
        link: currentUrl,
        item: items,
        allowEmpty: true,
    };
}
