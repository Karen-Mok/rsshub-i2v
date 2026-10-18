import { load } from 'cheerio';

import type { DataItem, Route } from '@/types';
import cache from '@/utils/cache';
import got from '@/utils/got';
import { parseDate } from '@/utils/parse-date';
import timezone from '@/utils/timezone';

const rootUrl = 'https://www.nia.gov.cn';

export const route: Route = {
    path: '/tzgg',
    categories: ['government'],
    example: '/nia/tzgg',
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
            source: ['www.nia.gov.cn/n741440/n741542/index.html'],
            target: '/tzgg',
        },
    ],
    name: '通知公告',
    maintainers: ['karenmok'],
    handler,
    url: 'www.nia.gov.cn/n741440/n741542/index.html',
    description: '国家移民管理局「通知公告」栏目。出入境政策、免签/过境免签调整多在此首发。',
};

async function handler(ctx) {
    const limit = ctx.req.query('limit') ? Number(ctx.req.query('limit')) : 15;
    const currentUrl = `${rootUrl}/n741440/n741542/index.html`;

    const { data: response } = await got(currentUrl);
    const $ = load(response);

    const list = ($('a[href*="content.html"]')
        .toArray()
        .map((item) => {
            const $item = $(item);
            const href = $item.prop('href');
            if (!href) {
                return null;
            }
            const link = href.startsWith('http') ? href : new URL(href, currentUrl).href;
            const title = $item.text().trim();
            if (!title) {
                return null;
            }
            // 日期在相邻的 <span style="width:120px;">2026-09-14</span>
            const dateText = $item.parent().find('span').last().text().match(/20\d{2}-\d{2}-\d{2}/) || $item.next('span').text().match(/20\d{2}-\d{2}-\d{2}/);
            return {
                title,
                link,
                pubDate: dateText ? timezone(parseDate(dateText[0]), +8) : undefined,
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
                    const description = $$('#content').html();
                    if (description) {
                        item.description = description;
                        item.content = { html: description, text: $$('#content').text().trim() };
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
        title: '国家移民管理局-通知公告',
        link: currentUrl,
        item: items,
        allowEmpty: true,
    };
}
