# v2node
A v2board backend base on moddified xray-core.
一个基于修改版xray内核的V2board节点服务端。

**注意： 本项目需要搭配[修改版V2board](https://github.com/wyx2685/v2board)**

## 软件安装

### 一键安装

```
wget -N https://raw.githubusercontent.com/wyx2685/v2node/master/script/install.sh && bash install.sh
```

## 构建
``` bash
GOEXPERIMENT=jsonv2 go build -v -o build_assets/v2node -trimpath -ldflags "-X 'github.com/wyx2685/v2node/cmd.version=$version' -s -w -buildid="
```

## Docker 运行

项目可以直接构建为 Docker 镜像运行。Linux VPS 推荐使用 `network_mode: host`，这样面板下发的节点端口、证书验证端口等不需要逐个映射；如果不用 host 网络，请自行用 `-p` 或 Compose `ports` 映射所有需要监听的端口。

### 多机器部署

如果你有很多台机器，推荐使用自己的 fork 发布镜像：

1. Fork 本仓库，并把 Docker 改动推到你的 fork。
2. 到 GitHub 仓库的 `Actions` 页面启用 workflow。
3. 运行 `Publish Docker image`，或等待后续 push/release 自动构建。
4. 当前 fork 的镜像地址为 `ghcr.io/movecat/pnode:latest`。如果是私有仓库或私有 package，需要先在服务器执行 `docker login ghcr.io`；推荐把 GHCR package 设为 public。

仓库内的 `Sync upstream` workflow 会每天合并 `https://github.com/wyx2685/v2node` 的 `main` 分支。同步成功后会触发 Docker 镜像重新构建；如果上游改动与本 fork 的 Docker 改动冲突，workflow 会失败，需要手动解决冲突。

### 一键 Docker 安装

当前 fork 已经把 `script/install-docker.sh` 的 `DEFAULT_IMAGE` 设置为 `ghcr.io/movecat/pnode:latest`，可以像面板生成的原生命令一样使用：

``` bash
wget -N https://raw.githubusercontent.com/movecat/Pnode/main/script/install-docker.sh && bash install-docker.sh --api-host https://example.com --node-id 1 --api-key replace-with-your-api-key
```

也可以不修改脚本，直接在命令里传镜像：

``` bash
wget -N https://raw.githubusercontent.com/movecat/Pnode/main/script/install-docker.sh && bash install-docker.sh --image ghcr.io/movecat/pnode:latest --api-host https://example.com --node-id 1 --api-key replace-with-your-api-key
```

脚本会自动安装 Docker（如未安装）、写入 `/opt/v2node/data/config.json`、生成 `/opt/v2node/docker-compose.yml`，然后拉取镜像并启动容器。重复执行同一条命令会更新配置并拉取最新镜像。

注意：V2board 面板默认生成的命令仍然指向上游 `script/install.sh`，那是原生安装脚本。若要让面板自动显示 Docker 版一键命令，需要在面板代码中把安装命令模板改为你的 `script/install-docker.sh` 地址。

### Docker Compose

``` bash
cp .env.example .env
# 编辑 .env，填入 V2NODE_API_HOST、V2NODE_NODE_ID、V2NODE_API_KEY
docker compose -f docker-compose.example.yml up -d --build
```

首次启动时，如果 `/etc/v2node/config.json` 不存在，容器会根据 `.env` 中的变量生成配置文件，并持久化到 `./docker/v2node/config.json`。

### docker run

``` bash
docker build -t v2node:local --build-arg VERSION=local .
mkdir -p docker/v2node
cp config.example.json docker/v2node/config.json
# 编辑 docker/v2node/config.json
docker run -d \
  --name v2node \
  --restart unless-stopped \
  --network host \
  -v "$PWD/docker/v2node:/etc/v2node" \
  v2node:local
```

也可以不用手写配置，直接用环境变量生成：

``` bash
docker run -d \
  --name v2node \
  --restart unless-stopped \
  --network host \
  -e V2NODE_API_HOST="https://example.com/" \
  -e V2NODE_NODE_ID="1" \
  -e V2NODE_API_KEY="replace-with-your-api-key" \
  -v "$PWD/docker/v2node:/etc/v2node" \
  v2node:local
```

配置、自动申请的证书和相关运行文件都放在 `/etc/v2node`，建议始终挂载该目录。默认日志输出到容器标准输出，可用 `docker logs -f v2node` 查看。

## Stars 增长记录

[![Stargazers over time](https://starchart.cc/wyx2685/v2node.svg?variant=adaptive)](https://starchart.cc/wyx2685/v2node)
