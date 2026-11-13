# ncm-comment-api

[![Docker Image](https://img.shields.io/badge/docker-meidlinger1024%2Fncm--comment--api-blue)](https://hub.docker.com/r/meidlinger1024/ncm-comment-api)
[![License](https://img.shields.io/badge/license-GPL--3.0-green)](LICENSE)

基于 [api-enhanced](https://github.com/neteasecloudmusicapienhanced/api-enhanced) 的网易云音乐
评论查询服务，提供歌曲评论的分页查询、多维度排序、楼中楼、热评、评论统计等能力，
并统一了请求参数与响应格式。

## 特性

- **兼容旧版接口**：根路径 `/` 保留经典评论列表接口的参数与响应字段，已有客户端无需改动。
- **完整分页**：支持按推荐、热度、时间三种排序分页获取评论，返回总数、页数和是否还有下一页。
- **楼中楼**：评论列表可直接附带二级评论，也可通过独立接口按楼层继续翻页。
- **更多查询**：热评、评论统计（评论数 / 点赞 / 分享）、歌曲信息、关键词搜索。
- **多资源类型**：歌曲、MV、歌单、专辑、电台节目、视频的评论均可查询。
- **统一响应**：所有接口（含错误）返回同一套 `{ code, msg, body }` 信封。

## 架构

```
客户端 ──> ncm-comment-api ──GET──> api-enhanced ──> 网易云
            参数解析 / 转发 / 统一响应格式
```

本服务通过 HTTP 对接 api-enhanced 提供的接口，对外暴露更简洁、统一的评论查询 API。

完整接口文档见 **[docs/API.md](docs/API.md)**。

## 快速开始

### Docker

```sh
docker run -d --name ncm-comment-api \
  -p 8383:8383 \
  -e WYY_API_BASE_URL=http://127.0.0.1:3000 \
  --restart unless-stopped \
  meidlinger1024/ncm-comment-api:latest
```

### Docker Compose

```yaml
services:
  ncm-comment-api:
    image: meidlinger1024/ncm-comment-api:latest
    container_name: ncm-comment-api
    ports:
      - "8383:8383"
    environment:
      PORT: 8383
      WYY_API_BASE_URL: http://127.0.0.1:3000
      API_USERNAME: ""
      API_PASSWORD: ""
    restart: unless-stopped
```

### 从源码运行

```sh
dart pub get
dart run bin/ncm_comment_api.dart
```

## 使用示例

```sh
# 经典评论列表接口：按歌名 + 歌手获取评论
curl 'http://127.0.0.1:8383/?song_name=晴天&singer_name=周杰伦&album_name=叶惠美'

# 按热度分页获取评论
curl 'http://127.0.0.1:8383/api/comments?song_id=186016&sort=hot&page=1&pageSize=20'

# 获取某条评论下的楼中楼
curl 'http://127.0.0.1:8383/api/replies?id=186016&comment_id=4956438&limit=20'

# 获取评论统计
curl 'http://127.0.0.1:8383/api/stats?id=186016'
```

## 接口一览

| 接口 | 说明 |
|---|---|
| `GET /` | 评论列表：`song_name` + `singer_name` + 可选 `album_name` |
| `GET /api/comments` | 分页评论，推荐 / 热度 / 时间排序，可附带楼中楼 |
| `GET /api/hot` | 热评 |
| `GET /api/replies` | 某条评论下的二级评论，可翻页 |
| `GET /api/stats` | 评论数 / 点赞 / 分享 / 乐评数 |
| `GET /api/search` | 关键词搜索歌曲 / 歌手 / 专辑 / 歌单 / MV / 用户 |
| `GET /api/song` | 歌曲信息 + 评论数 + 红心数 |

响应示例：

```json
{
  "code": 200,
  "msg": "success",
  "body": { }
}
```

参数、字段含义、分页方式与解析示例详见 **[docs/API.md](docs/API.md)**。

## 配置

支持 `config.conf` 配置文件和环境变量，环境变量优先级更高。
配置文件首次启动时自动生成，键名保持稳定，已有部署的配置可直接复用。

```ini
[api]
wyy_api_base_url=http://127.0.0.1:3000
default_port=8383
username=
password=
upstream_timeout=30
max_replies_per_comment=500
cache_ttl=60
```

| 环境变量 | 说明 | 默认值 |
|---|---|---|
| `WYY_API_BASE_URL` | api-enhanced 地址 | `http://127.0.0.1:3000` |
| `PORT` | 监听端口 | `8383` |
| `API_USERNAME` / `API_PASSWORD` | 非空则启用 token 校验（sha256 摘要） | 空 |
| `UPSTREAM_TIMEOUT` | 上游请求超时（秒） | `30` |
| `MAX_REPLIES_PER_COMMENT` | 单页每层楼最多拉取的回复数 | `500` |
| `CACHE_TTL` | 上游响应缓存时长（秒），`0` 为关闭 | `60` |

### Token 校验

当 `username` 或 `password` 非空时，所有接口都需要携带 `token` 参数：

```text
token = sha256(username + password + wyy_api_base_url)
```

## 构建

### 本地构建镜像

镜像只包含编译好的二进制，构建分两步：

```sh
dart pub get
dart compile exe bin/ncm_comment_api.dart -o build/ncm_comment_api-amd64
docker build --platform linux/amd64 -t ncm-comment-api .
```

（本机是 arm64 时把 `amd64` 换成 `arm64`，`TARGETARCH` 会选中对应二进制。）

### 自动构建发布

推送 `v*` 标签即自动构建并发布多架构镜像到 Docker Hub：

```sh
git tag v1.0.0
git push origin v1.0.0
```

流程（`.github/workflows/docker-publish.yml`）：

1. **test**：`dart pub get` → `dart analyze --fatal-infos` → `dart test`，任一失败则不再发布
2. **compile**：`linux/amd64`、`linux/arm64` 各自在对应架构的 runner 上原生编译，二进制作为 artifact 传给下一步
3. **publish**：一次多平台 `buildx` 构建，把两个二进制打进同一个镜像并推送

Docker Hub 上只会产生 `meidlinger1024/ncm-comment-api` 一个仓库。

生成镜像标签：`1.0.0`、`1.0`、`latest`；`docker pull` 会自动选择对应架构。

需要在仓库 `Settings → Secrets and variables → Actions` 中配置：

| Secret | 说明 |
|---|---|
| `DOCKERHUB_USERNAME` | Docker Hub 用户名 |
| `DOCKERHUB_TOKEN` | Docker Hub Access Token |

默认推送到 `meidlinger1024/ncm-comment-api`，可通过仓库变量 `DOCKERHUB_REPO` 覆盖。
也可在 Actions 页面手动触发（`workflow_dispatch`），支持指定额外标签。

## 开发

```sh
dart pub get     # 安装依赖
dart analyze     # 静态检查
dart test        # 运行测试
```

## 致谢

- [api-enhanced](https://github.com/neteasecloudmusicapienhanced/api-enhanced)：上游数据接口

## License

[GPL-3.0](LICENSE)
