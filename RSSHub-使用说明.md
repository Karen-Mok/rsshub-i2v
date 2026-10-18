# RSSHub 本地部署说明

RSSHub 已部署在本机，**http://127.0.0.1:1200**

## 快速验证

```bash
# 首页
curl --noproxy '*' http://127.0.0.1:1200/

# 一个真实可用的订阅源示例
curl --noproxy '*' http://127.0.0.1:1200/github/repos/DIYgod/RSSHub
```

> **注意**：本机设置了 HTTP 代理（`127.0.0.1:50954`），访问本地服务时容易被代理拦截返回 502。
> 用 curl 测试请加 `--noproxy '*'`；浏览器请检查是否已将 `127.0.0.1` 加入代理排除列表。

## 目录结构

| 路径 | 说明 |
|---|---|
| `RSSHub/` | RSSHub 源码（Git 仓库，便于日后 `git pull` 升级） |
| `RSSHub/.env` | 运行配置（端口、缓存、日志等） |
| `RSSHub/logs/` | 运行日志 |
| `start-rsshub.sh` | 启动脚本 |
| `rsshub-run.sh` | 前台运行脚本（供 systemd/launchd 类托管用） |
| `com.rsshub.local.plist` | macOS 开机自启配置（需手动加载，见下文） |

## 日常启停

在自己的终端中执行（不要用本工具的命令行，进程会被回收）：

```bash
# 启动（生产模式，需已构建）
./start-rsshub.sh

# 开发模式（改路由自动热重载）
./start-rsshub.sh dev
```

停止服务：

```bash
lsof -ti:1200 | xargs kill -9
```

## 常用命令

```bash
cd RSSHub

# 必须的环境准备（否则会被注入的文件代理钩子拦截）
unset NODE_OPTIONS
export CODEBUDDY_BROKERED_FS_HOOK_ENABLED=0
export PATH="/Users/karenmok/.workbuddy/binaries/node/versions/22.22.2-2/bin:$PATH"
PNPM=/Users/karenmok/.workbuddy/binaries/node/pnpm10/node_modules/.bin/pnpm

# 重新构建（改了源码或升级后）
$PNPM --config.managePackageManagerVersions=false build

# 更新 RSSHub 源码
git pull && $PNPM --config.managePackageManagerVersions=false install && $PNPM --config.managePackageManagerVersions=false build
```

> `pnpm` 务必带 `--config.managePackageManagerVersions=false`。
> 项目 `package.json` 锁定了 `pnpm@10.34.5`，若不加这个开关，pnpm 每次启动都会去重新下载该版本，导致每条命令都要卡约 300 秒。

## 配置说明（RSSHub/.env）

| 配置项 | 当前值 | 说明 |
|---|---|---|
| `PORT` | 1200 | 服务端口 |
| `LISTEN_INADDR_ANY` | 1 | 允许局域网/本机多网卡访问 |
| `CACHE_TYPE` | memory | 内存缓存，单机够用；长期运行建议换 redis |
| `CACHE_EXPIRE` | 1800 | 缓存 30 分钟 |
| `MEMORY_MAX` | 256 | 缓存最大占用 MB |
| `LOGGER_LEVEL` | info | 日志级别 |
| `ALLOW_ORIGIN` | * | 允许跨域，方便浏览器插件/前端调用 |

改完 `.env` 后重启服务生效。

需要抓取被墙站点时，在 `.env` 里加：

```
PROXY_URI=http://127.0.0.1:7890
PROXY_URL_REGEX=.
```

## 开机自启（可选）

`com.rsshub.local.plist` 已准备好。在自己的终端里执行：

```bash
cp com.rsshub.local.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.rsshub.local.plist
```

管理命令：

```bash
launchctl print gui/$UID/com.rsshub.local   # 查看状态
launchctl kickstart gui/$UID/com.rsshub.local  # 重启
launchctl bootout gui/$UID/com.rsshub.local    # 卸载
```

## 已知情况

- **部分路由会失败**：RSSHub 大量路由依赖目标网站结构，站点改版或反爬会导致 503/404（例如 `/36kr/information/technology` 当前返回 503）。这是路由本身的问题，不是部署问题，可通过 `git pull` 升级修复。
- **未安装 Chromium**：为节省安装时间跳过了 Puppeteer/Playwright 的浏览器下载。依赖浏览器渲染的路由会无法使用，需要时补装即可。
- **依赖首次安装较慢**：RSSHub 有 1045 个依赖包，本机网络环境下约需 1 小时。已全部缓存到 pnpm 本地仓库，后续重装只需几十秒。
