import 'dart:convert';

import 'package:ncm_comment_api/app.dart';
import 'package:ncm_comment_api/app_config.dart';
import 'package:ncm_comment_api/service/comment_query.dart';
import 'package:ncm_comment_api/util/https_utils.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// The routes, exercised end to end against a fake upstream.
///
/// The fake answers the api-enhanced endpoints this service reads, with records
/// copied from real answers, so the tests pin both the routing and the parsing
/// without touching the network.
class FakeUpstream extends UpstreamClient {
  FakeUpstream() : super(baseUrl: 'http://fake', cacheTtl: Duration.zero);

  final List<String> calls = [];

  @override
  Future<XResponse> get(String path, [Map<String, dynamic>? params]) async {
    calls.add('$path?${Uri(queryParameters: {for (final e in (params ?? {}).entries) e.key: '${e.value}'}).query}');

    switch (path) {
      case '/cloudsearch':
      case '/search':
        final keywords = '${params?['keywords']}';
        if (keywords.contains('nothing')) {
          return XResponse(body: {'code': 200, 'result': {'songs': [], 'songCount': 0}});
        }
        return XResponse(
          body: {
            'code': 200,
            'result': {
              'songCount': 1,
              'songs': [
                {
                  'id': 186016,
                  'name': '晴天',
                  'artists': [
                    {'name': '周杰伦'},
                  ],
                  'album': {'name': '叶惠美', 'picUrl': 'http://cover'},
                  'duration': 269000,
                },
              ],
            },
          },
        );
      case '/comment/new':
        final page = int.tryParse('${params?['pageNo']}') ?? 1;
        final sort = '${params?['sortType']}';
        if (sort == '3') {
          // The time order pages by cursor: the answer carries the cursor the
          // next page is asked with, and a page past the first without one is
          // empty. This mirrors what api-enhanced really does.
          // The upstream ignores a cursor that arrives with a page number the
          // cursor has not reached yet; this mirrors that.
          final cursor = '${params?['cursor'] ?? ''}';
          final pageNo = int.tryParse('${params?['pageNo']}') ?? 1;
          final times = switch (cursor) {
            '' || '0' => pageNo == 1 ? [5000, 4000] : <int>[],
            '4000' => [3000, 2000],
            '2000' => [4, 6],
            _ => <int>[],
          };
          return XResponse(
            body: {
              'code': 200,
              'data': {
                'totalCount': 6,
                'hasMore': times.isNotEmpty,
                'cursor': times.isEmpty ? '0' : '${times.last}',
                'comments': [
                  for (final time in times)
                    {
                      'commentId': time,
                      'content': 'at $time',
                      'time': time * 1000,
                      'likedCount': 1,
                      'user': {'nickname': 'n'},
                    },
                ],
              },
            },
          );
        }
        return XResponse(
          body: {
            'code': 200,
            'data': {
              'totalCount': 45,
              'hasMore': page < 3,
              'comments': [
                _comment(1000 + page, '顶层评论 $page', replies: 2),
                _comment(2000 + page, '没有回复的评论', replies: 0),
              ],
            },
          },
        );
      case '/comment/floor':
        return XResponse(
          body: {
            'code': 200,
            'data': {
              'totalCount': 2,
              'hasMore': false,
              'comments': [
                {
                  'commentId': 954000,
                  'content': '楼中楼',
                  'likedCount': 5,
                  'time': 1600000000000,
                  'timeStr': '2020-09-13',
                  'parentCommentId': params?['parentCommentId'],
                  'beReplied': [
                    {'beRepliedCommentId': params?['parentCommentId'], 'content': '被回复的原文'},
                  ],
                  'user': {'userId': 42, 'nickname': '路人', 'avatarUrl': 'http://avatar'},
                },
              ],
            },
          },
        );
      case '/comment/music':
        return XResponse(body: {'code': 200, 'hotComments': [_comment(1234501, '热评原文')], 'comments': []});
      case '/comment/info/list':
        return XResponse(
          body: {
            'code': 200,
            'data': [
              {
                'resourceId': 186016,
                'threadId': 'R_SO_4_186016',
                'commentCount': 70417,
                'commentCountDesc': '7w+',
                'likedCount': 55,
                'shareCount': 47715,
                'musicianSaidCount': 3,
              },
            ],
          },
        );
      case '/song/red/count':
        return XResponse(body: {'code': 200, 'data': {'count': 10585470}});
      case '/song/detail':
        return XResponse(
          body: {
            'code': 200,
            'songs': [
              {
                'id': 186016,
                'name': '晴天',
                'ar': [
                  {'name': '周杰伦'},
                ],
                'al': {'name': '叶惠美', 'picUrl': 'http://cover'},
                'dt': 269000,
              },
            ],
          },
        );
      default:
        return XResponse(body: {'code': 404}, code: 404);
    }
  }

  Map<String, dynamic> _comment(int id, String content, {int replies = 0}) => {
    'commentId': id,
    'content': content,
    'likedCount': 823201,
    'time': 1413530574000,
    'timeStr': '2014-10-17',
    'replyCount': replies,
    'showFloorComment': {'replyCount': replies},
    'ipLocation': {'location': '重庆'},
    'user': {
      'userId': 90210,
      'nickname': '听歌的人',
      'avatarUrl': 'http://avatar.jpg',
      'vipType': 11,
    },
  };
}

Future<Response> call(Handler app, String url) async {
  return await app(Request('GET', Uri.parse('http://localhost$url')));
}

Future<Map<String, dynamic>> bodyOf(Response response) async => jsonDecode(await response.readAsString()) as Map<String, dynamic>;

void main() {
  late FakeUpstream upstream;
  late Handler app;

  setUp(() {
    upstream = FakeUpstream();
    app = buildApp(
      config: AppConfig(
        wyyApiBaseUrl: 'http://fake',
        port: 8383,
        username: '',
        password: '',
        cacheTtl: Duration.zero,
      ),
      upstream: upstream,
    );
  });

  group('review_api root', () {
    test('answers 400 params error without both names', () async {
      final response = await call(app, '/?song_name=晴天');
      expect(response.statusCode, 400);
      expect(await response.readAsString(), 'params error');
    });

    test('answers the review_api envelope with review_api fields', () async {
      final response = await call(app, '/?song_name=晴天&singer_name=周杰伦');
      expect(response.statusCode, 200);
      final body = await bodyOf(response);
      expect(body['code'], 200);
      expect(body['msg'], 'success');
      final list = body['body'] as List;
      expect(list, isNotEmpty);

      final first = list.first as Map<String, dynamic>;
      // The fields review_api guaranteed, unchanged in name and type.
      expect(first['id'], '186016');
      expect(first['commentId'], isNotEmpty);
      expect(first['nick'], isNotEmpty);
      expect(first['avatarurl'], isNotEmpty);
      expect(first['content'], isNotEmpty);
      expect(first['praiseNum'], isA<int>());
      expect(first['createTime'], isA<int>());
      expect(first['type'], isA<int>());
    });

    test('answers an empty list when the song cannot be found', () async {
      final response = await call(app, '/?song_name=nothing&singer_name=周杰伦');
      final body = await bodyOf(response);
      expect(body['code'], 200);
      expect(body['body'], isEmpty);
    });
  });

  group('GET /api/comments', () {
    test('answers a page with totals and reply counts', () async {
      final response = await call(app, '/api/comments?song_name=晴天&singer_name=周杰伦&pageSize=2&reply_limit=2');
      expect(response.statusCode, 200);
      final body = await bodyOf(response);
      final page = body['body'] as Map<String, dynamic>;

      expect(page['total'], 45);
      expect(page['page'], 1);
      expect(page['pageSize'], 2);
      expect(page['pageCount'], 23);
      expect(page['hasMore'], true);

      final comments = page['comments'] as List;
      expect(comments.length, 2);
      final first = comments.first as Map<String, dynamic>;
      expect(first['replies'], isNotEmpty);
      expect((first['replies'] as List).first['parentCommentId'], '${first['commentId']}');
      expect(comments.last['replies'], isEmpty);
      expect(page['hotComments'], isNotEmpty);
    });

    test('accepts a song id and skips search', () async {
      upstream.calls.clear();
      final response = await call(app, '/api/comments?song_id=186016&reply_limit=0&hot=0');
      expect(response.statusCode, 200);
      expect(upstream.calls.any((c) => c.startsWith('/search')), isFalse);
      final page = (await bodyOf(response))['body'] as Map<String, dynamic>;
      expect(page['resolvedBy'], 'id');
      expect(page['hotComments'], isEmpty);
      expect((page['comments'] as List).first['replies'], isEmpty);
    });

    test('rejects a request that names nothing', () async {
      final response = await call(app, '/api/comments');
      expect(response.statusCode, 400);
      final body = await bodyOf(response);
      expect(body['code'], 400);
      expect(body['msg'], contains('params error'));
    });

    test('answers 404 for a name that matches nothing', () async {
      final response = await call(app, '/api/comments?song_name=nothing');
      expect(response.statusCode, 404);
    });
  });

  group('time order', () {
    test('first page hands back a cursor', () async {
      final response = await call(app, '/api/comments?song_id=186016&sort=time&pageSize=2&hot=0&reply_limit=0');
      final page = (await bodyOf(response))['body'] as Map<String, dynamic>;
      expect(page['sort'], 'time');
      expect((page['comments'] as List).length, 2);
      expect(page['nextCursor'], '4000');
    });

    test('page 3 walks the cursor instead of asking pageNo=3', () async {
      final response = await call(app, '/api/comments?song_id=186016&sort=time&pageSize=2&page=3&hot=0&reply_limit=0');
      final page = (await bodyOf(response))['body'] as Map<String, dynamic>;
      expect((page['comments'] as List).map((c) => c['createTime']), [4000, 6000]);
    });

    test('a cursor reads its page directly', () async {
      final response = await call(app, '/api/comments?song_id=186016&sort=time&pageSize=2&cursor=4000&hot=0&reply_limit=0');
      final page = (await bodyOf(response))['body'] as Map<String, dynamic>;
      expect((page['comments'] as List).map((c) => c['createTime']), [3000000, 2000000]);
    });
  });

  group('other endpoints', () {
    test('/api/replies asks comment/floor and keeps the parent id', () async {
      final response = await call(app, '/api/replies?id=186016&comment_id=1001');
      final body = await bodyOf(response);
      final data = body['body'] as Map<String, dynamic>;
      expect(data['commentId'], '1001');
      expect((data['replies'] as List).first['parentCommentId'], '1001');
    });

    test('/api/stats maps comment/info/list', () async {
      final response = await call(app, '/api/stats?id=186016');
      final data = (await bodyOf(response))['body'] as Map<String, dynamic>;
      expect(data['commentCount'], 70417);
      expect(data['commentCountDesc'], '7w+');
      expect(data['typeName'], 'song');
    });

    test('/api/search maps hits', () async {
      final response = await call(app, '/api/search?keywords=晴天');
      final data = (await bodyOf(response))['body'] as Map<String, dynamic>;
      final songs = data['songs'] as List;
      expect(songs.first['id'], '186016');
      expect(songs.first['artist'], '周杰伦');
    });
  });

  group('token', () {
    test('is enforced when configured', () async {
      app = buildApp(
        config: AppConfig(wyyApiBaseUrl: 'http://fake', port: 8383, username: 'u', password: 'p'),
        upstream: upstream,
      );
      final refused = await call(app, '/?song_name=晴天&singer_name=周杰伦');
      expect(refused.statusCode, 403);
      expect(await refused.readAsString(), 'missing token');
    });
  });

  test('sort codes accepted', () {
    expect(CommentSort.parse('hot'), CommentSort.hot);
    expect(CommentSort.parse('2'), CommentSort.hot);
    expect(CommentSort.parse('time'), CommentSort.time);
    expect(CommentSort.parse('3'), CommentSort.time);
    expect(CommentSort.parse('99'), CommentSort.recommended);
    expect(CommentSort.parse('1'), CommentSort.recommended);
    expect(CommentSort.parse('nonsense'), CommentSort.recommended);
  });
}
