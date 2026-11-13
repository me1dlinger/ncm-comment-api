# ncm-comment-api

网易云音乐评论查询服务。它部署在 [api-enhanced](https://github.com/neteasecloudmusicapienhanced/api-enhanced)
后面，**不自己访问网易云**：所有数据都来自你部署的 api-enhanced，本服务只负责参数解析、
转发和统一响应格式。

- 根路径 `/` 与 [review_api](https://github.com/amcfy-music/review_api) **完全兼容**，
  老客户端不用改。
- `/api/*` 提供更多评论查询：分页、排序、热评、楼中楼、评论统计、搜索、歌曲详情。
- 完整接口文档见 **[docs/API.md](docs/API.md)**。

## 快速开始

```sh
docker run -p 8383:8383 \
  -e WYY_API_BASE_URL=http://127.0.0.1:3000 \
  meidlinger1024/ncm-comment-api:latest
```

```sh
# review_api 兼容
curl 'http://127.0.0.1:8383/?song_name=晴天&singer_name=周杰伦&album_name=叶惠美'
# 分页评论（按热度，每页 20）
curl 'http://127.0.0.1:8383/api/comments?song_name=晴天&singer_name=周杰伦&album_name=叶惠美&sort=hot&page=1'
# 楼中楼
curl 'http://127.0.0.1:8383/api/replies?id=186016&comment_id=4956438'
```

## 接口一览

| 接口 | 说明 |
|---|---|
| `GET /` | review_api 兼容：`song_name` + `singer_name` + 可选 `album_name` |
| `GET /api/comments` | 分页评论，推荐/热度/时间排序，可带楼中楼 |
| `GET /api/hot` | 热评 |
| `GET /api/replies` | 某条评论下的二级评论，可翻页 |
| `GET /api/stats` | 评论数 / 点赞 / 分享 / 乐评数 |
| `GET /api/search` | 关键词搜歌/歌手/专辑/歌单/MV/用户 |
| `GET /api/song` | 歌曲信息 + 评论数 + 红心数 |

除根路径的 400 错误外，所有接口统一返回：

```json
{ "code": 200, "msg": "success", "body": { } }
```

参数、字段、分页与解析方式详见 [docs/API.md](docs/API.md)。

## 配置

`config.conf`（不存在会自动生成）或环境变量，环境变量优先。
键名与 review_api 保持一致，旧配置文件可直接使用：

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

| 环境变量 | 说明 |
|---|---|
| `WYY_API_BASE_URL` | api-enhanced 地址 |
| `PORT` | 监听端口 |
| `API_USERNAME` / `API_PASSWORD` | 非空则启用 token 校验（算法与 review_api 相同） |
| `UPSTREAM_TIMEOUT` | 上游超时秒数 |
| `MAX_REPLIES_PER_COMMENT` | 单页每层楼最多回复数 |
| `CACHE_TTL` | 上游缓存秒数，0 关闭 |

## 从源码运行

```sh
dart pub get
dart test
dart run bin/ncm_comment_api.dart
```

## 构建 Docker 镜像

GitHub Actions 在打 `v*` tag 或手动触发时构建 `linux/amd64` + `linux/arm64` 并推送到
Docker Hub（见 `.github/workflows/docker-publish.yml`）。

```sh
docker build -t ncm-comment-api .
```

## 依赖的上游接口

本服务只调用 api-enhanced 的这些 GET 接口：

`/cloudsearch`、`/search`、`/comment/new`、`/comment/music`（及 `/comment/mv` 等）、
`/comment/floor`、`/comment/info/list`、`/song/detail`、`/song/red/count`。

## License

GPL-3.0，见 [LICENSE](LICENSE)。
