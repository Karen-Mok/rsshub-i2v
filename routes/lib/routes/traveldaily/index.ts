import { load } from 'cheerio';

import type { DataItem, Route } from '@/types';
import cache from '@/utils/cache';
import got from '@/utils/got';
import { parseDate } from '@/utils/parse-date';
import timezone from '@/utils/timezone';

const rootUrl = 'https://www.traveldaily.cn';

export const route: Route = {
    path: '/:channel?',
    categories: ['new-media'],
    example: '/traveldaily/airline',
    parameters: { channel: '频道，默认全部。如 `airline`（航空）、`ai`（AI）等，对应 `https://www.traveldaily.cn/airline/`' },
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
            source: ['www.traveldaily.cn/:channel/'],
            target: '/:channel',
        },
    ],
    name: '资讯',
    maintainers: ['karenmok'],
    handler,
    url: 'www.traveldaily.cn',
    description: '环球旅讯。旅游科技、OTA/分销、商旅资讯。',
};

async function handler(ctx) {
    const { channel = '' } = ctx.req.param();
    const limit = ctx.req.query('limit') ? Number(ctx.req.query('limit')) : 15;
    const currentUrl = channel ? `${rootUrl}/${channel.replace(/^\//, '').replace(/\/$/, '')}/` : `${rootUrl}/`;

    const { data: response } = await got(currentUrl);
    const $ = load(response);

    const list = $('a[href*="/article/"]')
        .toArray()
        .map((item) => {
            const $item = $(item);
            const href = $item.prop('href');
            if (!href) {
                return null;
            }
            const link = href.startsWith('http') ? href : new URL(href, rootUrl).href;
            // 标题在卡片内，取卡片里较长的文本
            const title = ($item.prop('title') || $item.text()).replace(/\s+/g, ' ').trim();
            if (!title) {
                return null;
            }
            return { title, link } as DataItem;
        })
        .filter(Boolean) as DataItem[];

    const seen = new Set<string>();
    const uniq = list.filter((item) => {
        const id = item.link!.replace(/\/$/, '');
        if (seen.has(id)) {
            return false;
        }
        seen.add(id);
        return true;
    }).slice(0, limit);

    const items = await Promise.all(
        uniq.map((item) =>
            cache.tryGet(item.link!, async () => {
                try {
                    const { data: detail } = await got(item.link);
                    const $$ = load(detail);
                    const description = $$('[class*="__articleContent"]').html();
                    if (description) {
                        item.description = description;
                        item.content = { html: description, text: $$('[class*="__articleContent"]').text().trim() };
                    }
                    const title = $$('[class*="__articleHeader"] h1, h1').first().text().trim();
                    if (title) {
                        item.title = title;
                    }
                    const dateText = $$.text().match(/20\d{2}-\d{2}-\d{2}(?:\s+\d{2}:\d{2})?/);
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
        title: channel ? `环球旅讯-${channel}` : '环球旅讯',
        link: currentUrl,
        item: items,
        allowEmpty: true,
    };
}
