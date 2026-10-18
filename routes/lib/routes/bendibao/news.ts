import { load } from 'cheerio';

import InvalidParameterError from '@/errors/types/invalid-parameter';
import type { DataItem, Route } from '@/types';
import cache from '@/utils/cache';
import got from '@/utils/got';
import { parseDate } from '@/utils/parse-date';
import timezone from '@/utils/timezone';
import { isValidHost } from '@/utils/valid-host';

export const route: Route = {
    path: '/news/:city',
    categories: ['new-media'],
    example: '/bendibao/news/bj',
    parameters: { city: '城市缩写，可在该城市页面的 URL 中找到' },
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
            source: ['bendibao.com/'],
        },
    ],
    name: '焦点资讯',
    maintainers: ['nczitzk'],
    handler,
    url: 'bendibao.com/',
    description: `| 城市名 | 缩写 |
| ------ | ---- |
| 北京   | bj   |
| 上海   | sh   |
| 广州   | gz   |
| 深圳   | sz   |

更多城市请参见 [这里](http://www.bendibao.com/city.htm)

> **香港特别行政区** 和 **澳门特别行政区** 的本地宝城市页面不更新资讯。`,
};

async function handler(ctx) {
    const city = ctx.req.param('city');
    if (!isValidHost(city)) {
        throw new InvalidParameterError('Invalid city');
    }

    const limit = ctx.req.query('limit') ? Number(ctx.req.query('limit')) : 20;
    const rootUrl = `http://${city}.bendibao.com`;

    const response = await got({
        method: 'get',
        url: rootUrl,
    });

    const $ = load(response.data);
    const title = $('title')
        .text()
        .replace(/-爱上本地宝，生活会更好.*/, '');

    const list = $('a[href$=".shtm"]')
        .toArray()
        .map((item): DataItem | null => {
            const $item = $(item);
            const href = $item.attr('href');
            const text = $item.text().trim();
            if (!href || !text || !href.includes('.bendibao.com/')) {
                return null;
            }
            return {
                title: text,
                link: href.startsWith('http') ? href : `${rootUrl}${href}`,
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
                    const content = load(detailResponse.data);

                    const description = content('.article-content').html() ?? content('div.content').html() ?? content('div.content-box').html();
                    if (description) {
                        item.description = description;
                        item.content = { html: description, text: (content('.article-content').text() || content('div.content').text()).trim() };
                    }

                    const dateText =
                        content('span.time')
                            .text()
                            .replace(/发布时间：/, '') ||
                        content('span.public_time').text() ||
                        content.text().match(/20\d{2}[-/年]\d{1,2}[-/月]\d{1,2}(?:日)?(?:\s*\d{1,2}:\d{2})?/)?.[0] ||
                        '';
                    if (dateText) {
                        item.pubDate = timezone(parseDate(dateText), 8);
                    }
                } catch {
                    // 详情页失败时保留列表页信息
                }
                return item;
            })
        )
    );

    return {
        title: `${title}焦点资讯`,
        link: rootUrl,
        item: items,
        allowEmpty: true,
    };
}
