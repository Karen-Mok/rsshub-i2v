import { load } from 'cheerio';

import type { DataItem, Route } from '@/types';
import cache from '@/utils/cache';
import got from '@/utils/got';
import { parseDate } from '@/utils/parse-date';
import timezone from '@/utils/timezone';

const rootUrl = 'http://www.caacnews.com.cn';

const channels = {
    '1/1': '要闻',
    '1/2': '新闻',
    '1/3': '民航运输',
    '1/5': '航空安全',
    '1/6': '通用航空',
};

export const route: Route = {
    path: '/:channel{.+}?',
    categories: ['traditional-media'],
    example: '/caacnews/1/1',
    parameters: { channel: '栏目路径，默认 `1/1`（要闻）。可在频道页 URL 中截取，如 `http://www.caacnews.com.cn/1/1/index.html` → `1/1`' },
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
            source: ['www.caacnews.com.cn/:channel/index.html'],
            target: '/:channel',
        },
    ],
    name: '新闻频道',
    maintainers: ['karenmok'],
    handler,
    url: 'www.caacnews.com.cn',
    description: `中国民航网（中国民航报官网）。注意站点仅支持 http，https 握手会失败。

| 栏目 | 路径 |
| ---- | ---- |
| 要闻 | 1/1 |
| 新闻 | 1/2 |
| 民航运输 | 1/3 |
| 航空安全 | 1/5 |
| 通用航空 | 1/6 |`,
};

async function handler(ctx) {
    const { channel = '1/1' } = ctx.req.param();
    const limit = ctx.req.query('limit') ? Number(ctx.req.query('limit')) : 15;
    const currentUrl = `${rootUrl}/${channel.replace(/^\//, '').replace(/\/$/, '')}/index.html`;

    const { data: response } = await got(currentUrl);
    const $ = load(response);

    const list = ($('a[href*="t20"]')
        .toArray()
        .map((item) => {
            const $item = $(item);
            const href = $item.prop('href');
            if (!href || href === '' || href === '#') {
                return null;
            }
            const link = href.startsWith('http') ? href : new URL(href, currentUrl).href;
            // 仅保留新闻文章链接（/栏目/栏目/yyyymm/tXXXXXXXX_NNNNNNN.html），排除"关于我们"等导航页
            if (!/\/\d+\/\d+\/\d{6}\/t\d{8}_\d+\.html/.test(new URL(link).pathname)) {
                return null;
            }
            const m = link.match(/t(\d{4})(\d{2})(\d{2})_/);
            const title = $item.text().trim();
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
                    const description = $$('div.TRS_Editor').html() || $$('.TRS_Editor').html();
                    if (description) {
                        item.description = description;
                        item.content = { html: description, text: $$('.TRS_Editor').text().trim() };
                    }
                    const dateText = $$('.t1_td2_02').text().match(/20\d{2}-\d{2}-\d{2}(?:\s+\d{2}:\d{2}(?::\d{2})?)?/);
                    if (dateText) {
                        item.pubDate = timezone(parseDate(dateText[0]), +8);
                    }
                    const source = $$('#docsource').text().trim();
                    if (source) {
                        item.author = source;
                    }
                } catch {
                    // 详情页失败时保留列表页信息
                }
                return item;
            })
        )
    );

    return {
        title: `中国民航网-${channels[channel] ?? channel}`,
        link: currentUrl,
        item: items,
        allowEmpty: true,
    };
}
