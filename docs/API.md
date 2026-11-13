# ncm-comment-api 接口文档

基于 [api-enhanced](https://github.com/neteasecloudmusicapienhanced/api-enhanced) 的
网易云音乐评论查询服务。上游为已部署的 api-enhanced 实例，通过 `wyy_api_base_url` 配置。

- 根路径 `/`：经典评论列表接口，参数与响应字段保持不变，已有客户端可直接使用。
- `/api/*`：分页、排序、楼中楼、热评、统计、搜索等评论查询接口。

---

## 目录

1. [部署与配置](#1-部署与配置)
2. [通用约定](#2-通用约定)
3. [接口清单](#3-接口清单)
4. [GET / — 评论列表接口](#4-get---评论列表接口)
5. [GET /api/comments — 分页评论](#5-get-apicomments--分页评论)
6. [GET /api/hot — 热评](#6-get-apihot--热评)
7. [GET /api/replies — 楼中楼（二级评论）](#7-get-apireplies--楼中楼二级评论)
8. [GET /api/stats — 评论统计](#8-get-apistats--评论统计)
9. [GET /api/search — 搜索](#9-get-apisearch--搜索)
10. [GET /api/song — 歌曲信息](#10-get-apisong--歌曲信息)
11. [字段参考](#11-字段参考)
12. [错误与排错](#12-错误与排错)

---

## 1. 部署与配置

### 前置条件

先部署 api-enhanced（默认 `http://127.0.0.1:3000`），确认这些接口可用：

```sh
curl 'http://127.0.0.1:3000/comment/new?type=0&id=186016&pageNo=1&pageSize=2&sortType=2'
curl 'http://127.0.0.1:3000/song/detail?ids=186016'
```

### Docker

```sh
docker run -p 8383:8383 \
  -e PORT=8383 \
  -e WYY_API_BASE_URL=http://127.0.0.1:3000 \
  meidlinger1024/ncm-comment-api:latest
```

### 二进制 / 源码运行

```sh
dart pub get
dart run bin/ncm_comment_api.dart
```

首次运行会在当前目录生成 `config.conf`。也可以直接用环境变量，环境变量优先。

### 配置项

| config.conf 键 | 环境变量 | 默认值 | 说明 |
|---|---|---|---|
| `wyy_api_base_url` | `WYY_API_BASE_URL` | `http://127.0.0.1:3000` | api-enhanced 地址 |
| `default_port` | `PORT` | `8383` | 监听端口 |
| `username` | `API_USERNAME` | 空 | 非空即启用 token 校验 |
| `password` | `API_PASSWORD` | 空 | 同上 |
| `upstream_timeout` | `UPSTREAM_TIMEOUT` | `30` | 单次上游请求超时（秒） |
| `max_replies_per_comment` | `MAX_REPLIES_PER_COMMENT` | `500` | 单页每层楼最多拉多少条回复 |
| `cache_ttl` | `CACHE_TTL` | `60` | 上游回答缓存秒数，`0` 关闭 |

### token 校验

当 `username` 或 `password` 任一非空时，**所有接口**都要求带 `token` 参数：

```
token = sha256(username + password + wyy_api_base_url)
```

缺失返回 HTTP 403 `missing token`，错误返回 HTTP 403 `invalid token`（纯文本）。

---

## 2. 通用约定

### 请求

- 所有接口都是 **GET**，参数放在 query string。
- 中文参数需要 URL 编码。
- `OPTIONS` 请求返回 CORS 预检头，`Access-Control-Allow-Origin: *`。

### 响应信封

除根路径的错误响应外，**所有接口（含失败）**都返回同一种 JSON 信封：

```json
{
  "code": 200,
  "msg": "success",
  "body": { }
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `code` | int | `200` 成功；失败时为 HTTP 状态码（400/404/502） |
| `msg` | string | `success` 或错误说明 |
| `body` | object / array / null | 数据，失败时为 `null` |

HTTP 状态码与 `code` 一致，可以只看 HTTP 状态码判断成功与否。

### 分页语义

`/api/comments` 的 `page` 从 **1** 开始，`pageSize` 默认 20、上限 100：

- `pageSize` 取值 1–100（超出按边界处理）。
- 响应里同时给出 `page`（1 起）和 `pageNo`（0 起，api-enhanced 的叫法）。
- `total` 为网易云统计的评论总数；`pageCount = ceil(total / pageSize)`。
- `hasMore` 表示后面还有没有。

### 排序

`sort` 参数接受三种写法：

| 取值 | 含义 | 对应 api-enhanced `sortType` |
|---|---|---|
| `recommended`（默认）、`99`、`1` | 推荐排序（客户端默认） | `99` |
| `hot`、`2` | 按热度（点赞数） | `2` |
| `time`、`3` | 按时间（最新） | `3` |

> **注意**：`time` 排序下网易云是**游标分页**，不是页码分页。本服务已处理：
> 你照常传 `page=2` 即可，服务内部会顺着上游对话式游标走。也可以自己传
> `cursor`（取上一页响应的 `nextCursor`）直接读某一页，性能更好。

### 资源类型 `type`

评论接口不限于歌曲，`type` 支持（与 api-enhanced 相同）：

| type | 资源 |
|---|---|
| `0` / `song` | 歌曲 |
| `1` / `mv` | MV |
| `2` / `playlist` | 歌单 |
| `3` / `album` | 专辑 |
| `4` / `dj` | 电台节目 |
| `5` / `video` | 视频 |

不传默认歌曲。按歌名查询（`song_name`）只对 `song` 有效。

---

## 3. 接口清单

| 接口 | 作用 | 上游 api-enhanced 接口 |
|---|---|---|
| `GET /` | 评论列表：按歌名取评论 | `/cloudsearch` 或 `/search`、`/comment/new`、`/comment/music` |
| `GET /api/comments` | 分页评论（推荐/热度/时间），可带楼中楼 | `/comment/new`、`/comment/music`、`/comment/floor` |
| `GET /api/hot` | 热评 | `/comment/music`（无热评时回退 `/comment/new`） |
| `GET /api/replies` | 某条评论下的二级评论，可翻页 | `/comment/floor` |
| `GET /api/stats` | 评论数/点赞/分享/乐评数 | `/comment/info/list` |
| `GET /api/search` | 按关键词搜歌/歌手/专辑/歌单/MV/用户 | `/cloudsearch` |
| `GET /api/song` | 歌曲信息 + 评论数 + 红心数 | `/song/detail`、`/comment/info/list`、`/song/red/count` |

---

## 4. `GET /` — 评论列表接口

经典评论列表接口，参数与响应字段保持不变，已有客户端无需改动。

### 请求参数

| 参数 | 必填 | 说明 |
|---|---|---|
| `song_name` | 是 | 歌名 |
| `singer_name` | 是 | 歌手；缺任一返回 HTTP 400 `params error` |
| `album_name` | 否 | 专辑名。强烈建议传：不传时搜索结果里翻唱/上传版可能排在原曲之前 |
| `token` | 视配置 | 见上文 token 校验 |

### 示例

```
GET /?song_name=晴天&singer_name=周杰伦&album_name=叶惠美
```

### 响应

```json
{
  "code": 200,
  "msg": "success",
  "body": [
    {
      "id": "186016",
      "commentId": "4956438",
      "nick": "蛋蛋是圆D",
      "avatarurl": "http://p3.music.126.net/...jpg",
      "content": "…",
      "praiseNum": 823204,
      "createTime": 1413530574,
      "type": 1,
      "createTimeMillis": 1413530574297,
      "createTimeStr": "2014-10-20",
      "ipLocation": "…",
      "isHot": true,
      "avatarUrl": "http://p3.music.126.net/...jpg",
      "userId": "…",
      "isVip": true,
      "vipType": 11,
      "parentCommentId": "",
      "replyCount": 0,
      "replies": [],
      "repliesHasMore": false
    }
  ]
}
```

`id` / `commentId` / `nick` / `avatarurl` / `content` / `praiseNum` / `createTime` / `type`
这 8 个字段的名称与类型保持稳定，其余为扩展字段，旧客户端可忽略。

- 返回内容 = 热评 + 一页普通评论（最多约 50 条），热评在前。
- `type`：`1` 热评，`2` 普通评论。
- 找不到歌时返回 `{"code":200,"msg":"success","body":[]}`。

### 解析要点

- `praiseNum` 是点赞数，降序看 `isHot` 为 true 的即热评。
- `createTime` 是**秒**，`createTimeMillis` 是毫秒。
- 想拿完整评论而不是一页，改用 [`/api/comments`](#5-get-apicomments--分页评论)。

---

## 5. `GET /api/comments` — 分页评论

核心接口。可按歌名或歌 id 取任意一页评论，带总数、排序和楼中楼。

### 请求参数

| 参数 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `id` 或 `song_id` | 二选一 | — | 资源 id（歌曲 id 等）。给了 id 就跳过搜索 |
| `song_name` | 二选一 | — | 歌名，配合 `singer_name` / `album_name` 解析出 id |
| `singer_name` 或 `artist` | 否 | 空 | 歌手，提高解析准确率 |
| `album_name` | 否 | 空 | 专辑，强烈建议与歌名一起传 |
| `type` | 否 | `0` | 资源类型，见[资源类型](#资源类型-type)；按名查询只支持 `0` |
| `page` | 否 | `1` | 页码，从 1 开始，最大 1000 |
| `pageSize` | 否 | `20` | 每页条数，最大 100 |
| `sort` | 否 | `recommended` | `recommended` / `hot` / `time`（或 1/99、2、3） |
| `cursor` | 否 | — | `sort=time` 时可传上一页的 `nextCursor` 直接读该页 |
| `hot` | 否 | `true` | 首页是否附带热评（`hot=0` 关闭） |
| `reply_limit` | 否 | `3` | 每条评论附带几条楼中楼，`0` 关闭（关闭后最快） |

### 示例

按歌名取第 2 页、按热度、每条带 2 条楼中楼：

```
GET /api/comments?song_name=晴天&singer_name=周杰伦&album_name=叶惠美&page=2&pageSize=10&sort=hot&reply_limit=2
```

按歌曲 id 取最新评论第一页：

```
GET /api/comments?song_id=186016&sort=time&pageSize=20&reply_limit=0
```

### 响应

```json
{
  "code": 200,
  "msg": "success",
  "body": {
    "song": {
      "songId": "186016",
      "id": "186016",
      "name": "晴天",
      "artist": "周杰伦",
      "album": "叶惠美",
      "coverUrl": "http://p4.music.126.net/...jpg",
      "duration": 269000
    },
    "id": "186016",
    "type": 0,
    "typeName": "song",
    "resolvedBy": "search",
    "total": 1969877,
    "page": 1,
    "pageNo": 0,
    "pageSize": 20,
    "pageCount": 98494,
    "hasMore": true,
    "sort": "recommended",
    "nextCursor": null,
    "repliesPerComment": 3,
    "hotComments": [ { 评论对象 }, … ],
    "comments": [ { 评论对象 }, … ]
  }
}
```

| 字段 | 说明 |
|---|---|
| `song` | 歌曲信息。按 id 查询且未做搜索时大多为空串（传 `id` 不会多花一次请求去查详情） |
| `resolvedBy` | `search`（按歌名搜到的）/ `id`（调用方直接给的 id） |
| `total` | 评论总数（网易云统计值） |
| `page` / `pageNo` | 1 起 / 0 起页码 |
| `pageCount` | 总页数 |
| `hasMore` | 后面还有没有 |
| `sort` | 实际使用的排序名 |
| `nextCursor` | `sort=time` 时下一页要用的游标（其他排序为 `null`） |
| `repliesPerComment` | 实际附带的楼中楼条数 |
| `hotComments` | 热评，仅首页且 `hot` 未关闭时非空 |
| `comments` | 本页评论，每条内含 `replies` |

### 分页用法

```
第 1 页：/api/comments?song_id=186016&page=1&pageSize=20
第 2 页：/api/comments?song_id=186016&page=2&pageSize=20
结束条件：响应 body.hasMore == false
```

按时间翻页建议用游标（少走 N 次上游请求）：

```
第 1 页：…&sort=time              → 记下 body.nextCursor
第 2 页：…&sort=time&cursor=<nextCursor>
```

### 解析要点

- 评论对象字段见[字段参考](#11-字段参考)。
- `comments[i].replies` 是楼中楼，`repliesHasMore` 表示这层楼还有更多回复没取，需要更多就用 [`/api/replies`](#7-get-apireplies--楼中楼二级评论) 翻。
- 歌名匹配不到时 HTTP 404，`msg` 为 `song not found: …`。

---

## 6. `GET /api/hot` — 热评

### 请求参数

| 参数 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `id` 或 `song_id` | 是 | — | 资源 id |
| `type` | 否 | `0` | 资源类型 |
| `limit` | 否 | `20` | 条数，1–100 |

### 示例

```
GET /api/hot?id=186016
GET /api/hot?id=5436712&type=mv
```

### 响应

```json
{
  "code": 200,
  "msg": "success",
  "body": {
    "id": "186016",
    "type": 0,
    "typeName": "song",
    "total": 15,
    "hotComments": [ { 评论对象 }, … ]
  }
}
```

- 数据来自 api-enhanced `/comment/music` 的 `hotComments`。
- 该接口没有热评段时，回退为“按热度排序的前 N 条”（`isHot` 仍为 `true`）。

---

## 7. `GET /api/replies` — 楼中楼（二级评论）

取某条评论下所有回复，可分页。

### 请求参数

| 参数 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `id` 或 `song_id` | 是 | — | 资源 id（评论所属的歌曲） |
| `comment_id` 或 `parentCommentId` | 是 | — | 父评论 id（一级评论的 `commentId`） |
| `type` | 否 | `0` | 资源类型 |
| `limit` | 否 | `20` | 每页条数，1–100 |
| `time` | 否 | `-1` | 翻页参数：传上一页的 `nextTime`；第一页不传 |

### 示例

```
GET /api/replies?id=186016&comment_id=4956438&limit=20
GET /api/replies?id=186016&comment_id=4956438&limit=20&time=1554221438912
```

### 响应

```json
{
  "code": 200,
  "msg": "success",
  "body": {
    "id": "186016",
    "type": 0,
    "typeName": "song",
    "commentId": "4956438",
    "total": 14,
    "hasMore": true,
    "nextTime": "1554221438912",
    "replies": [
      {
        "commentId": "1436921389",
        "nick": "湘江去北",
        "content": "我",
        "parentCommentId": "4956438",
        "createTime": 1436921389,
        "createTimeMillis": 1436921389000,
        "praiseNum": 12,
        "type": 2,
        "replies": [],
        …
      }
    ]
  }
}
```

### 解析要点

- `parentCommentId` 指向它回复的一级评论（楼中楼的 id）。
- `hasMore=false` 时到底；否则用 `nextTime` 作为下一请求的 `time`。
- 某条回复回复的是楼中另一条回复时，`beReplied` 细节不单独暴露，只给 `parentCommentId`（楼中楼归属到楼），需要“回复谁”的场景可按 `createTimeMillis` 显示楼层顺序即可。

---

## 8. `GET /api/stats` — 评论统计

一次拿到歌曲页面上那几个数字。

### 请求参数

| 参数 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `id` 或 `song_id` | 是 | — | 资源 id |
| `type` | 否 | `0` | 资源类型 |

### 示例

```
GET /api/stats?id=186016
```

### 响应

```json
{
  "code": 200,
  "msg": "success",
  "body": {
    "id": "186016",
    "type": 0,
    "typeName": "song",
    "threadId": "R_SO_4_186016",
    "commentCount": 1969877,
    "commentCountDesc": "100w+",
    "likedCount": 352,
    "shareCount": 109723,
    "musicianCommentCount": 0
  }
}
```

| 字段 | 说明 |
|---|---|
| `commentCount` | 评论总数（整数） |
| `commentCountDesc` | 网易云展示用的缩写（`7w+` / `100w+`） |
| `likedCount` | 评论区被点赞数 |
| `shareCount` | 分享数 |
| `musicianCommentCount` | 歌手本人的评论数 |
| `threadId` | 网易云评论线程 id |

上游失败时 HTTP 502。

---

## 9. `GET /api/search` — 搜索

把歌名解析成 `songId` 用，也可以找歌手/专辑/歌单/MV/用户。

### 请求参数

| 参数 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `keywords` 或 `query` | 是 | — | 关键词，如 `晴天 周杰伦` |
| `type` | 否 | `1`（歌曲） | `1` 歌曲、`100` 歌手、`10` 专辑、`1000` 歌单、`1004` MV、`1002` 用户；也可传 `song`/`artist`/`album`/`playlist`/`mv`/`user` |
| `limit` | 否 | `30` | 条数，1–100 |

### 示例

```
GET /api/search?keywords=晴天 周杰伦&limit=5
GET /api/search?keywords=周杰伦&type=artist
```

### 响应（歌曲）

```json
{
  "code": 200,
  "msg": "success",
  "body": {
    "keywords": "晴天 周杰伦",
    "type": 1,
    "total": 5,
    "songs": [
      {
        "kind": "song",
        "id": "186016",
        "name": "晴天",
        "artist": "周杰伦",
        "album": "叶惠美",
        "coverUrl": "http://p4.music.126.net/...jpg",
        "duration": 269000,
        "commentCount": -1,
        "popularity": -1
      }
    ]
  }
}
```

### 解析要点

- 字段名对所有类型统一：`kind` / `id` / `name` / `artist` / `album` / `coverUrl` / `duration`。
- 歌手/歌单等的 `id` 可直接用于 `/api/comments?type=…&id=…`。
- 得到的 `id` 传给 [`/api/song`](#10-get-apisong--歌曲信息) 可拿到 `commentCount` 和红心数。

---

## 10. `GET /api/song` — 歌曲信息

按 id 或歌名拿歌曲详情 + 评论数 + 红心数。

### 请求参数

| 参数 | 必填 | 说明 |
|---|---|---|
| `id` 或 `song_id` | 二选一 | 歌曲 id |
| `song_name` | 二选一 | 歌名，配合 `singer_name`/`album_name` |

### 示例

```
GET /api/song?id=186016
GET /api/song?song_name=晴天&singer_name=周杰伦&album_name=叶惠美
```

### 响应

```json
{
  "code": 200,
  "msg": "success",
  "body": {
    "songId": "186016",
    "id": "186016",
    "name": "晴天",
    "artist": "周杰伦",
    "album": "叶惠美",
    "coverUrl": "http://p4.music.126.net/...jpg",
    "duration": 269000,
    "commentCount": 1969877,
    "commentCountDesc": "100w+",
    "likedCount": 6823006
  }
}
```

| 字段 | 说明 |
|---|---|
| `duration` | 毫秒 |
| `commentCount` | 评论总数，`-1` 表示取不到 |
| `likedCount` | 红心（喜欢）数，`-1` 表示取不到 |

---

## 11. 字段参考

### 评论对象（`SongComment`）

出现在 `body`（根路径）、`body.comments`、`body.hotComments`、`body.replies`。

| 字段 | 类型 | 基础字段 | 说明 |
|---|---|---|---|
| `id` | string | ✅ | 所属资源 id（歌曲 id） |
| `commentId` | string | ✅ | 评论 id |
| `nick` | string | ✅ | 昵称 |
| `avatarurl` | string | ✅ | 头像 URL（全小写字段名） |
| `content` | string | ✅ | 评论内容 |
| `praiseNum` | int | ✅ | 点赞数 |
| `createTime` | int | ✅ | 发表时间，**秒** |
| `type` | int | ✅ | `1` 热评，`2` 普通评论（楼中楼也是 `2`） |
| `createTimeMillis` | int | ➕ | 发表时间，毫秒 |
| `createTimeStr` | string | ➕ | 网易云展示日期，如 `2014-10-20`、`09-13` |
| `ipLocation` | string | ➕ | IP 归属地 |
| `isHot` | bool | ➕ | 是否来自热评段 |
| `avatarUrl` | string | ➕ | 头像 URL（驼峰别名，与 `avatarurl` 同值） |
| `userId` | string | ➕ | 用户 id |
| `isVip` | bool | ➕ | 是否会员 |
| `vipType` | int | ➕ | 会员等级，0 为非会员 |
| `parentCommentId` | string | ➕ | 所属楼的一级评论 id；一级评论为空串 |
| `replyCount` | int | ➕ | 这层楼共有多少条回复 |
| `replies` | array | ➕ | 已拉取的楼中楼（最多 `reply_limit` 条） |
| `repliesHasMore` | bool | ➕ | `replies` 是否只是楼内前几条 |

> 只读上述 8 个基础字段即可正常工作，扩展字段按需使用。

### 歌曲对象（`song`）

| 字段 | 说明 |
|---|---|
| `songId` / `id` | 歌曲 id |
| `name` | 歌名 |
| `artist` | 歌手，多歌手用 `/` 连接 |
| `album` | 专辑名 |
| `coverUrl` | 封面 URL |
| `duration` | 时长（毫秒） |

---

## 12. 错误与排错

### 错误响应

| HTTP / code | 场景 |
|---|---|
| `400` | 缺必填参数。`msg` 形如 `params error: pass id (or song_id) or song_name` |
| `403` | 配了 username/password 但没带或带错 `token`（纯文本） |
| `404` | 资源不存在（如歌名搜不到），`msg` 形如 `song not found: …` |
| `502` | 上游 api-enhanced 读不到 / 返回失败 |
| `500` | 服务内部异常（`{"code":500,"msg":"internal error","body":null}`） |

根路径 `GET /` 的缺参数错误为 HTTP 400 + 纯文本 `params error`。

### 常见问题

**按歌名返回的评论不是原曲的**
搜索结果里翻唱、同名上传版可能排在原曲前。传 `album_name` 能显著提高准确率：

```
/api/comments?song_name=晴天&singer_name=周杰伦&album_name=叶惠美
```

**`sort=time` 第 2 页为空**
不应发生（服务内部走游标）。若自己实现客户端调上游，注意网易云时间排序是游标分页不是页码分页。

**根路径只返回几十条**
根路径按设计只返回热评 + 一页普通评论。要完整评论请用 `/api/comments` 分页。

**`reply_limit` 让请求变慢**
每条有回复的评论都要多一次上游请求。只看评论列表时传 `reply_limit=0` 最快。

**评论数对不上**
`total` 是网易云统计值，与 `pageCount * pageSize` 可能有出入属正常。
