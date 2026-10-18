# RSSHub 远程 Linux 服务器部署指南

把本地已配好的 **9 条自定义路由**（7 新增 + 2 修复）迁移到远程 Linux 服务器。

---

## 一、先搞清楚一件事：自定义路由为什么不能直接"拷过去用"

RSSHub 的路由是 **TypeScript 源码**，不是运行时配置。它们必须参与 `pnpm build` 才会被编译进 `dist/`。
所以流程一定是：

```
服务器 clone RSSHub 源码  →  覆盖自定义路由文件  →  安装依赖  →  构建  →  启动
```

**不能用官方 Docker 镜像 + 挂载路由文件**（镜像里的 dist 已编译好，挂载源码无效），必须用本目录的 `Dockerfile.custom` 自行构建镜像。

---

## 二、方案选择

| 方案 | 适用场景 | 维护成本 | 推荐度 |
|---|---|---|---|
| **源码 + systemd** | 长期运行的自有服务器 | 低（可 git 升级） | ⭐ 推荐 |
| Docker Compose | 已有 Docker 环境、想隔离 | 中（改路由要重新 build 镜像） | 备选 |
| Kubernetes | 已有 K8s 集群 | 高 | 不在本文范围 |

下面以**源码 + systemd** 为主线，Docker 方案见第六节。

---

## 三、完整步骤

### 第 1 步：本机导出路由包

```bash
cd /Users/karenmok/WorkBuddy/2026-09-18-09-55-46/server-deploy
bash export-routes.sh
```

产出 `rsshub-routes-<日期>.tar.gz`，内含：

```
routes/lib/routes/{caac,caacnews,mct,nia,atmb,ctaweb,traveldaily}/{namespace.ts,index.ts|xwzx.ts}
routes/lib/routes/bendibao/news.ts      # 修复版
routes/lib/routes/nbd/index.ts          # 修复版
COMMIT                                   # 本地 RSSHub 版本锚点（本次为 bf9504c045f4...）
MANIFEST.txt
```

> **为什么要 COMMIT 锚点**：RSSHub 上游改动频繁，路由 API 可能变化。
> 服务器必须 checkout 到同一个 commit，本地验证过的路由才能原样跑起来。

### 第 2 步：上传到服务器

```bash
scp rsshub-routes-<日期>.tar.gz root@<服务器IP>:/tmp/
scp deploy.sh                   root@<服务器IP>:/tmp/
```

### 第 3 步：服务器执行部署

```bash
ssh root@<服务器IP>
sudo bash /tmp/deploy.sh
```

脚本会自动完成：

1. 安装 Node.js 22.22.2（若已有 22+ 则跳过）
2. 安装 pnpm 10.34.5
3. 克隆 RSSHub 并 checkout 到匹配的 commit
4. 覆盖 16 个路由文件
5. `pnpm install`（用 npmmirror 镜像加速）
6. `pnpm build`
7. 写入 `.env`（端口、内存缓存、跨域等）
8. 创建 `rsshub` 系统用户 + systemd 服务
9. 启动并**逐条验证 9 个自定义路由**

### 第 4 步：放行端口

```bash
# CentOS / Rocky / AlmaLinux
firewall-cmd --add-port=1200/tcp --permanent && firewall-cmd --reload

# Ubuntu / Debian
ufw allow 1200/tcp
```

云服务器还需在**安全组**里放行 1200（或 Nginx 的 443）。

### 第 5 步：验证

```bash
# 本机
curl "http://<服务器IP>:1200/caac/xwzx/mhyw?limit=5"

# 服务器上
curl "http://127.0.0.1:1200/nia/tzgg?limit=5"
```

---

## 四、日常运维

```bash
systemctl status  rsshub            # 状态
systemctl restart rsshub            # 重启
systemctl stop    rsshub            # 停止
journalctl -u rsshub -f             # 实时日志
journalctl -u rsshub -n 100 --no-pager   # 最近 100 行
```

安装目录：`/opt/rsshub`
配置：`/opt/rsshub/.env`（改完 `systemctl restart rsshub`）
日志：`/opt/rsshub/logs/`

### 改端口 / 改安装目录

```bash
sudo bash /tmp/deploy.sh --port 8080 --dir /data/rsshub
```

### 生产环境加固（建议）

用 Nginx 反代 + HTTPS，不要直接把 1200 暴露到公网：

```bash
sudo cp nginx-rsshub.conf /etc/nginx/conf.d/rsshub.conf
sudo vim /etc/nginx/conf.d/rsshub.conf    # 改 server_name 和证书路径
sudo certbot --nginx -d rss.example.com   # 申请证书
sudo nginx -t && sudo systemctl reload nginx
```

---

## 五、升级（重要：自定义路由的坑）

升级会导致自定义路由**部分丢失**，必须按下面的顺序操作：

```bash
cd /opt/rsshub
git checkout master
git pull

# 重新应用自定义路由
tar -xzf /tmp/rsshub-routes-<日期>.tar.gz -C /tmp/restore --strip-components=0
cp -r /tmp/restore/routes/. /opt/rsshub/

# 重新构建
pnpm --config.managePackageManagerVersions=false install
pnpm --config.managePackageManagerVersions=false build

chown -R rsshub:rsshub /opt/rsshub
systemctl restart rsshub
```

**哪些会丢：**

| 类型 | 升级后是否保留 | 说明 |
|---|---|---|
| 7 个新增命名空间（caac/caacnews/...） | ✅ 保留 | 上游不会有同名目录，不会冲突 |
| 修改的 `bendibao/news.ts`、`nbd/index.ts` | ❌ **会被上游覆盖** | 必须重新覆盖，否则回到失效状态 |

**更稳的做法**（推荐长期用）：把自定义改动 fork 成自己的分支或单独仓库，升级时 rebase/cherry-pick，而不是每次手动拷。

---

## 六、Docker 方案（备选）

```bash
# 服务器上准备好目录结构
mkdir -p /opt/rsshub-docker && cd /opt/rsshub-docker
git clone --depth=1 https://github.com/DIYgod/RSSHub.git RSSHub
tar -xzf /tmp/rsshub-routes-<日期>.tar.gz -C /tmp && cp -r /tmp/routes/. RSSHub/

# 拷贝本目录的 Dockerfile.custom 与 docker-compose.yml 到此
docker compose up -d --build

# 验证
curl "http://127.0.0.1:1200/caac/xwzx/mhyw?limit=5"
```

后续改路由需要 `docker compose up -d --build`（重新构建镜像，约 2~5 分钟）。

---

## 七、踩坑清单（脚本已处理，这里说明原因）

| 坑 | 现象 | 解法 |
|---|---|---|
| **pnpm 版本自动管理** | 每条 pnpm 命令卡约 300 秒才执行 | 所有命令加 `--config.managePackageManagerVersions=false`。原因：项目 `package.json` 锁定了 `pnpm@10.34.5`，pnpm 默认每次启动都去解析/下载该版本 |
| **Node 版本** | 构建报 engines 错误 | 必须 `>= 22.22.2`，脚本会装 22.22.2 |
| **只监听 127.0.0.1** | 服务器本机 curl 通，外部访问不通 | `.env` 里 `LISTEN_INADDR_ANY=1` + 防火墙放行 |
| **国内拉 GitHub/npm 慢** | clone 超时、install 卡住 | 脚本已用 npmmirror；git 失败时自动回退 ghfast.top 镜像 |
| **统计条目数不准** | 用 `grep -c "<item>"` 恒为 1 | RSSHub 输出的 XML 是单行，要用 `awk -v RS='<item>' 'END{print NR-1}'` |
| **内存缓存撑爆** | 长期运行 OOM | `.env` 里 `MEMORY_MAX=512` 限流；生产建议换 Redis |
| **macOS 元数据文件** | build 报 `Unexpected "\x00"` / `._index.ts` | 见下面「故障排查」，跑 `fix-build.sh` |

---

## 七·五、故障排查

### ❌ 构建报 `Unexpected "\x00"` 或 `._index.ts`

```
Error [TransformError]: Transform failed with 1 error:
/opt/rsshub/lib/routes/atmb/._index.ts:1:0: ERROR: Unexpected "\x00"
```

**原因**：macOS 传输文件时混入的 **AppleDouble 元数据文件**（`._` 前缀）。这些是 Finder 存放扩展属性的隐藏文件，内容含二进制 `\x00`，Linux 上被 esbuild 当成 TypeScript 源码扫描就崩溃。

常见混入途径：`scp -r` / `rsync` 直接传目录、macOS 上用 Finder 压缩、另一台 Mac 用系统 tar 打包。

**修复（在服务器上）**：

```bash
sudo bash /tmp/fix-build.sh
```

脚本会：扫描并清理 `._*` / `.DS_Store` / `__MACOSX` → 校验 16 个路由文件齐全 → 重新构建 → 重启 → 逐条验证路由。

想先看会删什么而不实际删除：

```bash
sudo bash /tmp/fix-build.sh --dry-run
```

手动一行清理也行：

```bash
find /opt/rsshub -name '._*' -not -path '*/node_modules/.pnpm/*' -exec rm -rf {} +
```

**已做好的预防**（三道防线）：
1. `export-routes.sh` 设 `COPYFILE_DISABLE=1`，从源头禁止 macOS tar 生成 `._`
2. 打包时 `--exclude='._*'`，并自检包内是否残留
3. `deploy.sh` 在应用路由后、构建前各清理一次

### ⚠️ `WARN Unsupported engine: node v22.22.1`

RSSHub 要求 `^22.22.2 || ^24.15.0`，**22.22.1 差一个小版本**。这本身通常只是警告、不阻断构建，但建议补齐：

```bash
sudo bash /tmp/fix-build.sh --upgrade-node
```

新版 `deploy.sh` 已修正版本判定（原来只比主版本号，导致 22.22.1 被误判为合格），现在会正确触发安装 22.22.2。

### ⚠️ 构建成功但 `[FAIL] 服务未就绪` / `未找到 rsshub systemd 服务`

```
✔ Build complete in 104485ms
[ OK ] 构建完成
[WARN] 未找到 rsshub systemd 服务，请手动重启
[FAIL] 服务未就绪
```

**原因**：`deploy.sh` 的步骤是线性的，一旦在**构建阶段**失败中断，后面的
`.env` 写入、运行用户创建、systemd 服务安装、启动**全都不会执行**。
构建修好后，服务自然还是没有的。

**修复**：

```bash
sudo bash /tmp/fix-build.sh --skip-build
```

`--skip-build` 表示已经构建成功、不用再等 1~2 分钟，脚本只做：
补 `.env` → 补 `rsshub` 用户 → 建 systemd 服务 → 启动 → 验证 9 条路由。

新版 `fix-build.sh` 已具备"服务不存在就自动创建"的能力，不再只是重启。

> 构建输出里的 `TOLERATED_TRANSFORM ... Namespace tags` 是 **RSSHub 官方代码自带的无害警告**
> （`itunes:` / `atom:` / `rsshub:` 命名空间标签），本地构建同样会出现，看到 `✔ Build complete` 即成功。

### ⚠️ 验证路由时一条都没输出就回到提示符

**原因**：脚本用 `set -euo pipefail`，任一条路由 curl 超时会让 `n=$(curl | awk)` 的赋值语句
返回非零（`pipefail` 让管道继承 curl 的失败码），触发 `set -e` 直接静默退出。

已修复：验证阶段临时 `set +e`，且每条都显示 `HTTP=xxx 条目=N`，跑完 9 条才结束。

### ⚠️ 路由大面积 `HTTP=000` / 超时（境外服务器高发）

**先跑诊断**，别急着改路由代码：

```bash
bash /tmp/diag.sh
```

它会输出三部分：
1. 服务器出口 IP 与地理位置（判定是否境外）
2. 9 个目标站点的连通性（HTTP 码 + 耗时）
3. 9 条 RSSHub 路由的实测结果

并据此给出结论：**是服务器出网问题，还是路由代码问题**。

> **重要**：本项目的自定义路由抓的全是**国内政府与行业站点**
> （caac.gov.cn / nia.gov.cn / mct.gov.cn / atmb.net.cn 等）。
> 若部署在境外 VPS（Vultr / 搬瓦工 / AWS 海外区等），访问这些站点
> 延迟高、甚至被拦截，会大面积超时。**建议直接用境内服务器部署。**

境外部署的补救（需自备代理）：

```bash
cat >> /opt/rsshub/.env <<'EOF'
PROXY_URI=http://<代理地址>:<端口>
PROXY_URL_REGEX=.
EOF
systemctl restart rsshub
```

---

## 八、部署后的订阅地址

把对照表里的 `http://localhost:1200` 全部换成 `http://<服务器IP>:1200`（或你的域名）即可，例如：

| 源 | 地址 |
|---|---|
| 中国民航局 | `http://<服务器IP>:1200/caac/xwzx/mhyw` |
| 中国民航网 | `http://<服务器IP>:1200/caacnews/1/1` |
| 移民局 | `http://<服务器IP>:1200/nia/tzgg` |
| 文旅部 | `http://<服务器IP>:1200/mct/whzx/whyw` |
| 空管局 | `http://<服务器IP>:1200/atmb` |
| 环球旅讯 | `http://<服务器IP>:1200/traveldaily/airline` |
| 本地宝 | `http://<服务器IP>:1200/bendibao/news/bj` |
| 旅游研究院 | `http://<服务器IP>:1200/ctaweb` |
| 每经 | `http://<服务器IP>:1200/nbd` |

完整 50 个源见 `民航信息源-RSS订阅对照表.md`。

---

## 附：服务器最低配置建议

- CPU：2 核
- 内存：2 GB（内存缓存模式；换 Redis 可降到 1 GB）
- 磁盘：10 GB（源码 + node_modules + dist 约 3 GB）
- 系统：Ubuntu 22.04+ / Debian 12+ / CentOS 8+（需 systemd）
- 网络：能访问国内站点（政府类路由主要抓国内源）
