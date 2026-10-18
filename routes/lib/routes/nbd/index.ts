import { load } from 'cheerio';

import type { DataItem, Route } from '@/types';
import cache from '@/utils/cache';
import got from '@/utils/got';
import { parseDate } from '@/utils/parse-date';
import timezone from '@/utils/timezone';

export const route: Route = {
    path: '/:id?',
    categories: ['finance'],
    example: '/nbd',
    parameters: { id: '分类 id，见下表，默认为要闻' },
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
            source: ['nbd.com.cn/', 'nbd.com.cn/columns/:id?'],
        },
    ],
    name: '分类',
    maintainers: ['nczitzk'],
    handler,
    url: 'nbd.com.cn/',
    description: `| 头条 | 要闻 | 图片新闻 | 推荐 |
| ---- | ---- | -------- | ---- |
| 2    | 3    | 4        | 5    |`,
};

async function handler(ctx) {
    const limit = ctx.req.query('limit') ? Number(ctx.req.query('limit')) : 20;

    const rootUrl = 'https://www.nbd.com.cn';
    const currentUrl = `${rootUrl}/`;

    const response = await got({
        method: 'get',
        url: currentUrl,
    });

    const $ = load(response.data);

    const list = $('a[href*="/articles/"]')
        .toArray()
        .map((item): DataItem | null => {
            const $item = $(item);
            const href = $item.attr('href');
            const title = $item.text().trim();
            if (!href || !title) {
                return null;
            }
            const m = href.match(/\/articles\/(\d{4}-\d{2}-\d{2})\//);
            return {
                title,
                link: href.startsWith('http') ? href : new URL(href, rootUrl).href,
                pubDate: m ? parseDate(m[1]) : undefined,
            };
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
                    const detailResponse = await got({
                        method: 'get',
                        url: item.link,
                    });
                    if (!detailResponse.url.startsWith(`${rootUrl}/`)) {
                        return item;
                    }
                    const content = load(detailResponse.data);

                    const description = content('.g-articl-text').html();
                    if (description) {
                        item.description = description;
                        item.content = { html: description, text: content('.g-articl-text').text().trim() };
                    }
                    const dateMatch = detailResponse.data.match(/"pubDate":\s*"([^"]+)"/) || content.text().match(/20\d{2}-\d{2}-\d{2}(?:\s+\d{2}:\d{2})?/);
                    if (dateMatch) {
                        item.pubDate = timezone(parseDate(dateMatch[1] ?? dateMatch[0]), 8);
                    }
                } catch {
                    // 详情页失败时保留列表页信息
                }

                return item;
            })
        )
    );

    return {
        title: '每日经济新闻',
        link: currentUrl,
        item: items,
        allowEmpty: true,
    };
}
