import { load } from 'cheerio';

import type { DataItem, Route } from '@/types';
import cache from '@/utils/cache';
import got from '@/utils/got';
import { parseDate } from '@/utils/parse-date';
import timezone from '@/utils/timezone';

const rootUrl = 'http://www.atmb.net.cn';

export const route: Route = {
    path: '/',
    categories: ['government'],
    example: '/atmb',
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
            source: ['www.atmb.net.cn'],
            target: '/',
        },
    ],
    name: '最新动态',
    maintainers: ['karenmok'],
    handler,
    url: 'www.atmb.net.cn',
    description: '民航局空中交通管理局官网首页动态。流量管理、运行通告。',
};

// 空管局站点仅支持 http（https 握手会失败），且对部分来源 IP 敏感。
// 显式设置浏览器 UA 与较长超时，境外服务器部署时尤其需要。
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

async function handler(ctx) {
    const limit = ctx.req.query('limit') ? Number(ctx.req.query('limit')) : 15;
    const currentUrl = `${rootUrl}/`;

    // 重要：RSSHub 的 got 底层已是 ofetch（见 lib/utils/got.ts），
    // 不能传 got/axios 风格的 timeout 对象 —— 会被 AbortSignal.timeout() 转成 NaN 而立即超时。
    // 只设置 UA 即可，超时交给 RSSHub 全局配置。
    const { data: response } = await got(currentUrl, {
        headers: { 'User-Agent': UA },
    });
    const $ = load(response);

    const list = $('a[href*="ContentNew.aspx?newsid="]')
        .toArray()
        .map((item) => {
            const $item = $(item);
            const href = $item.prop('href');
            if (!href) {
                return null;
            }
            const link = href.startsWith('http') ? href : new URL(href, currentUrl).href;
            const title = ($item.prop('title') || $item.text()).trim();
            if (!title) {
                return null;
            }
            return { title, link } as DataItem;
        })
        .filter(Boolean) as DataItem[];

    // 去重（首页同一新闻可能出现图片/文字两个入口）
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
                    const { data: detail } = await got(item.link, {
                        headers: { 'User-Agent': UA },
                    });
                    const $$ = load(detail);
                    const description = $$('#contentshow').html();
                    if (description) {
                        item.description = description;
                        item.content = { html: description, text: $$('#contentshow').text().trim() };
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
        title: '民航局空管局-最新动态',
        link: currentUrl,
        item: items,
        allowEmpty: true,
    };
}
