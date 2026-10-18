# 民航情报系统 · 信息源 RSS 订阅对照表

> RSSHub 实例：`http://localhost:1200`（已本地部署并验证）
> 验证时间：2026-09-18 · 全部标注"✅ 实测"的链接均在本地实例实际请求通过
> 抓取字段：除特殊注明外，下列订阅源均提供 **标题 / 正文 / 发布时间 / 原文链接** 四个字段

## 一、总览

| 覆盖方式 | 数量 | 说明 |
|---|---|---|
| ① 官方 RSS 直接用 | 1 | OAG |
| ② RSSHub 已有路由（实测通过） | 15 | 政府/财经/热榜类 |
| ③ 本次新写/修复的 RSSHub 路由（实测通过） | 9 | 民航局、民航网、文旅部、移民局等 |
| ④ 公众号（需公众号采集层） | 9 | 见第四节统一方案 |
| ⑤ 暂无法覆盖/不稳定 | 17 | 原因见表内备注 |

**可直接订阅的合计 25 项（①+②+③）。**

---

## 二、可直接订阅（✅ 实测通过）

### A. 官方 RSS

| 源 | 原网址 | 官方RSS | 完整 RSS 链接 | 验证 |
|---|---|---|---|---|
| S26 OAG | oag.com | ✅ 是 | `https://www.oag.com/blog/rss.xml` | curl 实测 HTTP 200、`text/xml`，含标题/摘要/日期/链接 |

### B. RSSHub 已有路由（实测通过）

| 源 | 原网址 | RSSHub 路由路径 | 完整订阅链接 | 验证结果 |
|---|---|---|---|---|
| S03 中国政府网 | gov.cn | `/gov/zhengce/govall` | `http://localhost:1200/gov/zhengce/govall` | ✅ 20 条 |
| S04 国家发改委 | ndrc.gov.cn | `/gov/ndrc/xwdt/xwfb` | `http://localhost:1200/gov/ndrc/xwdt/xwfb` | ✅ 25 条（新闻发布） |
| S15 财联社 | cls.cn | `/cls/hot`、`/cls/depth` | `http://localhost:1200/cls/hot` ｜ `http://localhost:1200/cls/depth` | ✅ 13 / 32 条 |
| S16 澎湃新闻 | thepaper.cn | `/thepaper/featured`、`/thepaper/list/25457` | `http://localhost:1200/thepaper/featured` ｜ `http://localhost:1200/thepaper/list/25457` | ✅ 20 / 10 条 |
| S17 界面新闻 | jiemian.com | `/jiemian/lists/65` | `http://localhost:1200/jiemian/lists/65` | ✅ 9 条 |
| S18b 第一财经 | yicai.com | `/yicai/news` | `http://localhost:1200/yicai/news` | ✅ 30 条 |
| S29 隆众资讯 | oilchem.net | `/oilchem` | `http://localhost:1200/oilchem` | ✅ 20 条 |
| S31 金十数据 | jin10.com | `/jin10`、`/jin10/1`（重要） | `http://localhost:1200/jin10` ｜ `http://localhost:1200/jin10/1` | ✅ 20 / 8 条 |
| S32 华尔街见闻 | wallstreetcn.com | `/wallstreetcn/news` | `http://localhost:1200/wallstreetcn/news` | ✅ 35 条 |
| S34 中国外汇交易中心 | chinamoney.com.cn | `/chinamoney` | `http://localhost:1200/chinamoney` | ✅ 15 条（公告） |
| S42a 微博热搜 | weibo.com | `/tophub/KqndgxeLl9` | `http://localhost:1200/tophub/KqndgxeLl9` | ✅ 50 条 |
| S42b 抖音热榜 | douyin.com | `/tophub/DpQvNABoNE` | `http://localhost:1200/tophub/DpQvNABoNE` | ✅ 20 条 |
| S42c 百度热搜 | baidu.com | `/tophub/Jb0vmloB1G` | `http://localhost:1200/tophub/Jb0vmloB1G` | ✅ 51 条 |
| S45 国家统计局 | stats.gov.cn | `/gov/stats/sj/zxfb` | `http://localhost:1200/gov/stats/sj/zxfb` | ✅ 15 条 |
| S46 中央气象台 | nmc.cn | `/nmc/weatheralarm` | `http://localhost:1200/nmc/weatheralarm` | ✅ 20 条（全国预警） |
| S49 中国铁路/12306 | 12306.cn | `/12306/zxdt` | `http://localhost:1200/12306/zxdt` | ✅ 20 条（最新动态） |

### C. 本次新写/修复的 RSSHub 路由（实测通过）

| 源 | 原网址 | RSSHub 路由路径 | 完整订阅链接 | 抓取字段 | 验证结果 |
|---|---|---|---|---|---|
| S01 中国民航局 | caac.gov.cn | `/caac/xwzx/mhyw` | `http://localhost:1200/caac/xwzx/mhyw` | 标题/正文/日期/链接 | ✅ 8 条（民航要闻） |
| S02 中国民航网 | caacnews.com.cn | `/caacnews/1/1` | `http://localhost:1200/caacnews/1/1` | 标题/正文/日期/链接/来源 | ✅ 15 条（要闻） |
| S05 文化和旅游部 | mct.gov.cn | `/mct/whzx/whyw` | `http://localhost:1200/mct/whzx/whyw` | 标题/正文/日期/链接 | ✅ 15 条（文化要闻） |
| S07 国家移民管理局 | nia.gov.cn | `/nia/tzgg` | `http://localhost:1200/nia/tzgg` | 标题/正文/日期/链接 | ✅ 9 条（通知公告，含过境免签） |
| S14 环球旅讯 | traveldaily.cn | `/traveldaily/airline` | `http://localhost:1200/traveldaily/airline` | 标题/正文/日期/链接 | ✅ 12 条（航空频道） |
| S18a 每日经济新闻 | nbd.com.cn | `/nbd` | `http://localhost:1200/nbd` | 标题/正文/日期/链接 | ✅ 15 条（修复原失效路由） |
| S37 本地宝 | bj.bendibao.com | `/bendibao/news/bj` | `http://localhost:1200/bendibao/news/bj` | 标题/正文/日期/链接 | ✅ 20 条（修复；换城市改缩写） |
| S44 中国旅游研究院 | ctaweb.org.cn | `/ctaweb` | `http://localhost:1200/ctaweb` | 标题/正文/日期/链接 | ✅ 15 条（工作动态+通知公告） |
| S47 民航局空管局 | atmb.net.cn | `/atmb` | `http://localhost:1200/atmb` | 标题/正文/日期/链接 | ✅ 8 条（最新动态） |

---

## 三、部分覆盖 / 替代方案

| 源 | 原网址 | 现状 | 说明 |
|---|---|---|---|
| S06 领事直通车 | 微信公众号 | ⚠️ 替代 | 公众号本体需采集层（见第四节）。**替代**：`http://localhost:1200/gov/mfa/wjdt`（外交部动态，✅ 35 条，含领事司签证/领保信息） |

---

## 四、公众号类（需统一采集层）

微信公众号**无官方 RSS**，且反爬严格，无法靠普通网页抓取稳定获取。以下 9 个源同属此类，建议统一用一套"公众号采集层"解决，而不是逐个写路由：

| 源 | 说明 |
|---|---|
| S06 领事直通车 | 外交部领事司 |
| S12 航旅圈 | ★ 燃油附加费调整常首发 |
| S13 航旅通讯社 | 行业快讯 |
| S20 飞常准 | 《民航周报》、准点率月报 |
| S21 航班管家 | 民航运行周报 |
| S22 航旅纵横 | 节假日出行大数据 |
| S38 中国演出行业协会 | 演出市场季报 |
| S43 OTA 研究院 | 携程/同程/飞猪节假日预测 |
| S48 基地机场集团公众号 | 首都/上海/白云等机场一手信息 |

**采集层方案（按推荐度）：**

1. **自建 wechat2rss**（推荐）：开源项目，微信扫码登录后即可为每个公众号生成 RSS。RSSHub 已内置对接路由 `/wechat/wechat2rss/:id`，部署 wechat2rss 后在 `.env` 配置其地址即可，统一走 RSSHub 输出。
2. RSSHub 的 `/wechat/sogou/:id`（搜狗微信）目前被搜狗反爬拦截，不稳定，不建议依赖。
3. 第三方付费采集服务（如"新榜""微小宝"等）导出 RSS，稳定性取决于服务商。

> 结论：公众号源建议单独立项做采集层，不占本次 RSSHub 路由工作量。

---

## 五、暂无法覆盖 / 不稳定（附原因）

| 源 | 原网址 | 状态 | 具体原因 |
|---|---|---|---|
| S08 省文旅厅审批 | 各省文旅厅 | ⛔ 无通用路由 | 各省站点结构不一，需按重点城市逐个定制 |
| S09 地方政府 | 各城市门户 | ⛔ 需按城市 | RSSHub `gov` 命名空间含部分省市，需逐个验证后订阅 |
| S10 国家体育总局 | sport.gov.cn | ⛔ 无路由 | 赛历多为 PDF，按源清单建议人工录入年度事件表 |
| S11 民航资源网 CARNOC | carnoc.com | ⛔ 本次未覆盖 | 全站 JS 渲染 + 数据库查询接口（`db-query`），静态抓取不可得；建议 RSS-Bridge 全页快照或 puppeteer |
| S19 航班管家 DAST | dast.133.cn | ⛔ 数据平台 | 需注册登录的看板平台，无公开列表页，建议用其报表导出或页面抓数 |
| S23 民航局月度统计 | caac.gov.cn | ⛔ 本次未覆盖 | 统计栏目为新版 JS 渲染页，静态抓取不可得；月度公报**新闻稿**可由 `/caac/xwzx/mhyw` 间接获得 |
| S24 中国航空运输协会 | cata.org.cn | ⛔ 本次未覆盖 | 全站 JS 渲染（接口式），需按其 JSON 接口定制 |
| S25 IATA Economics | iata.org | ⛔ 无 RSS | 站点 JS 渲染，无公开 RSS；需定制或人工 |
| S27 CAPA | centreforaviation.com | ⛔ 本次未覆盖 | 无官方 RSS（有 sitemap），英文 JS 站，需定制路由 |
| S28 Routesonline | routesonline.com | ⛔ 不稳定 | Cloudflare 防护，curl 直连 403；RSSHub 服务端同样会被拦，需配代理/浏览器 |
| S30 金联创 | 315i.com | ⛔ 订阅制 | 付费墙，需账号 |
| S33 OPEC 官网 | opec.org | ⛔ 不稳定 | Cloudflare 挑战页（Just a moment），直连 403 |
| S35 大麦网 | 大麦 APP | ⛔ APP 数据 | 无网页列表与 RSS，按源清单建议人工周检或第三方数据服务 |
| S36 猫眼演出 | 猫眼 APP | ⛔ APP 数据 | 同上 |
| S39 会展排期 | eshow365 等 | ⛔ 不稳定 | eshow365 本机访问超时；会展站点质量参差，建议按月人工核对重点城市 |
| S40 大型博览会 | 各官方渠道 | ⛔ 固定届次 | 按源清单建议建"年度事件日历表"人工维护直接喂系统 |
| S41 马拉松/赛事平台 | 各赛事官网 | ⛔ 无统一源 | 站点分散，需定制或人工 |
| S50 AvHerald / ASN | avherald.com | ⛔ 无公开 RSS | 猜测的 RSS 路径均 404；ASN(aviation-safety.net) Cloudflare 403。源清单"avherald 支持原生 RSS"未能在本次验证 |

---

## 六、使用与维护说明

**新路由代码位置**（已并入本地 RSSHub，重启后生效）：

```
RSSHub/lib/routes/caac/xwzx.ts        # 民航局新闻中心（栏目可换 MHYW/DFDT/HYDT/MTZX/XWFBH）
RSSHub/lib/routes/caacnews/index.ts   # 中国民航网（/1/1 要闻，注意站点仅支持 http）
RSSHub/lib/routes/mct/index.ts        # 文旅部（栏目路径可换）
RSSHub/lib/routes/nia/index.ts        # 移民局通知公告
RSSHub/lib/routes/atmb/index.ts       # 空管局
RSSHub/lib/routes/ctaweb/index.ts     # 中国旅游研究院
RSSHub/lib/routes/traveldaily/index.ts# 环球旅讯
RSSHub/lib/routes/bendibao/news.ts    # 本地宝（修复）
RSSHub/lib/routes/nbd/index.ts        # 每经（修复）
```

**已失效的原内置路由（勿用）：**
- `/gov/zhengce/zuixin`、`/gov/cn/news/bm`、`/gov/zhengce/zhengceku/*`、`/gov/zhengce/wenjian`（gov.cn 改版，返回 503）
- `/chinania`（实为"中国有色金属工业协会"，非移民局，且目标站已失效）
- `/gov/caac/cjwt`（民航局"公众留言"，代码报错）

**注意事项：**
- 本机设有 HTTP 代理（`127.0.0.1:50954`），用 curl 验证本地 RSSHub 时务必加 `--noproxy '*'`；浏览器请把 `127.0.0.1` 加入代理排除。
- 每条订阅链接后均可加 `?limit=N` 控制条目数（默认 15~20）。
- 缓存 30 分钟；升级路由代码后需重启 RSSHub 生效。
