# rsshub-i2v

民航情报系统的数据源层：**RSSHub + 9 条自定义民航路由**。

用途：统一订阅民航/政务/财经/文旅信息源 → 筛选民航相关内容 → 交给 AI 分析，
输出市场收益、飞行运控方向的意见。

---

## 快速开始（服务器部署）

```bash
# 1. 克隆本仓库
sudo git clone https://github.com/Karen-Mok/rsshub-i2v.git /opt/rsshub-i2v
cd /opt/rsshub-i2v/server-deploy

# 2. 一键部署
sudo bash deploy.sh
```

装好后 RSSHub 运行在 `http://<服务器IP>:1200`，脚本末尾会**逐条验证 9 个自定义路由**。

> ⚠️ 必须 clone 整个仓库（脚本依赖 `../routes/`），只下载单个 `deploy.sh` 会报错退出。

详细步骤、参数、故障排查见 **[server-deploy/README-服务器部署.md](server-deploy/README-服务器部署.md)**。

---

## 目录结构

```
.
├── routes/                      # 自定义路由源码（部署时覆盖到 RSSHub）
│   ├── COMMIT                   # RSSHub 版本锚点 bf9504c045f4...
│   ├── MANIFEST.txt
│   └── lib/routes/
│       ├── caac/                中国民用航空局
│       ├── caacnews/            中国民航网
│       ├── mct/                 文化和旅游部
│       ├── nia/                 国家移民管理局
│       ├── atmb/                民航局空管局
│       ├── ctaweb/              中国旅游研究院
│       ├── traveldaily/         环球旅讯
│       ├── bendibao/news.ts     本地宝（修复失效选择器）
│       └── nbd/index.ts         每日经济新闻（修复失效选择器）
│
├── server-deploy/
│   ├── deploy.sh                一键部署（推荐入口）
│   ├── fix-build.sh             构建失败修复 / 补建服务
│   ├── diag.sh                  出网连通性诊断
│   ├── README-服务器部署.md      完整文档
│   ├── nginx-rsshub.conf        Nginx 反代 + HTTPS
│   ├── Dockerfile.custom        Docker 自建镜像
│   └── docker-compose.yml       Docker Compose
│
├── start-rsshub.sh / rsshub-run.sh    macOS 本地启动脚本
├── com.rsshub.local.plist             macOS launchd 服务
└── 民航信息源-RSS订阅对照表.md         50 个信息源的完整订阅对照表
```

> 路由以**源码目录**而非 tar.gz 存放：`.ts` 是纯文本，可 diff、可 review，
> 且 git 不会产生 macOS 的 `._` 文件（那个文件会让 esbuild 构建崩溃）。

---

## 订阅地址

| 源 | 路由 |
|---|---|
| 中国民航局 | `/caac/xwzx/mhyw` |
| 中国民航网 | `/caacnews/1/1` |
| 文化和旅游部 | `/mct/whzx/whyw` |
| 国家移民管理局 | `/nia/tzgg` |
| 民航局空管局 | `/atmb` |
| 中国旅游研究院 | `/ctaweb` |
| 环球旅讯 | `/traveldaily/airline` |
| 本地宝（换城市改缩写） | `/bendibao/news/bj` |
| 每日经济新闻 | `/nbd` |

另有 15 条 RSSHub 官方路由可直接使用（中国政府网、发改委、财联社、澎湃、界面、
隆众资讯、金十、华尔街见闻、统计局、中央气象台、12306、微博/抖音/百度热榜等），
完整清单见 **[民航信息源-RSS订阅对照表.md](民航信息源-RSS订阅对照表.md)**。

把对照表里的 `http://localhost:1200` 换成 `http://<服务器IP>:1200` 即可。

---

## 常用命令

```bash
# 服务
systemctl status|restart|stop rsshub
journalctl -u rsshub -f

# 重新部署（改了路由后必须加 --rebuild）
cd /opt/rsshub-i2v && git pull
cd server-deploy && sudo bash deploy.sh --rebuild

# 出问题时
sudo bash fix-build.sh --skip-build   # 已构建成功，只补服务并启动
bash diag.sh                          # 判断是出网问题还是路由问题
```

---

## 两个务必注意的点

**1. RSSHub 版本锚点**
自定义路由与上游 RSSHub 强耦合。`routes/COMMIT` 锁定了验证过的版本
（`bf9504c045f4...`），部署脚本会自动 checkout 到该 commit。
升级上游时改这个文件，然后 `--rebuild` 重新验证。

**2. 境外服务器**
本项目的路由目标几乎都是**国内政务站点**。
境外 VPS（Vultr / AWS 海外区等）可能有部分站点连不上——这是网络层问题，
改代码无解。实测某台境外机器 9 条路由中 8 条正常，空管局 `/atmb` 因
TCP 连接被拒（curl error 7）不可用。

部署后先跑 `bash diag.sh` 确认，它会判定"出网问题"还是"路由问题"并给出方案。
长期建议**境内服务器部署**。

---

## macOS 本地部署

```bash
bash start-rsshub.sh          # 前台启动
# 或用 launchd 常驻：
cp com.rsshub.local.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.rsshub.local.plist
```

详见 [RSSHub-使用说明.md](RSSHub-使用说明.md)。
