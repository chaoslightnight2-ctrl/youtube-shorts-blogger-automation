import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shorts_radar/data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('missing statistics remain null through a JSON round trip', () {
    final json = _feed();
    final first = (json['channels'] as List).first as Map<String, dynamic>;
    first['viewCount'] = null;
    first['subscriberCount'] = null;
    first['videos'] = [_video(0, views: null)];
    final parsed = Feed.fromJson(json);
    final roundTrip = Feed.fromJson(parsed.toJson());
    expect(roundTrip.channels.first.viewCount, isNull);
    expect(roundTrip.channels.first.subscriberCount, isNull);
    expect(roundTrip.channels.first.videos.first.viewCount, isNull);
    expect(roundTrip.channels.first.videos.first.likeCount, isNull);
  });

  test('shows only the ten newest videos, ordered by publish date', () {
    final json = _feed();
    (json['channels'] as List).first['videos'] =
        List.generate(15, (index) => _video(index));
    final videos = Feed.fromJson(json).channels.first.videos;
    expect(videos, hasLength(10));
    expect(videos.first.id, 'video14');
    expect(videos.last.id, 'video5');
  });

  test('a channel failure preserves all four channels and its error', () {
    final json = _feed();
    final failed = (json['channels'] as List)[2] as Map<String, dynamic>;
    failed['error'] = 'YouTube verisi geçici olarak alınamadı.';
    failed['viewCount'] = null;
    failed['videos'] = <Object>[];
    final feed = Feed.fromJson(json);
    expect(feed.channels, hasLength(4));
    expect(feed.channels[2].id, 'channel2');
    expect(feed.channels[2].error, contains('alınamadı'));
    expect(feed.channels[2].videos, isEmpty);
    expect(feed.channels[2].viewCount, isNull);
  });

  test('requires supported schema and four unique channels', () {
    final unsupported = _feed()..['schemaVersion'] = 2;
    expect(() => Feed.fromJson(unsupported), throwsA(isA<FeedException>()));
    final fewer = _feed();
    (fewer['channels'] as List).removeLast();
    expect(() => Feed.fromJson(fewer), throwsA(isA<FeedException>()));
    final duplicates = _feed();
    (duplicates['channels'] as List)[3]['id'] = 'channel0';
    expect(() => Feed.fromJson(duplicates), throwsA(isA<FeedException>()));
  });

  test('uses bundled snapshot and persists a successful refresh', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = FeedRepository(
      feedUrl: _url,
      preferences: prefs,
      assetBundle: _Bundle(_feed()),
      client: MockClient((request) async {
        expect(request.url.toString(), _url);
        return http.Response(jsonEncode(_feed(day: 22)), 200);
      }),
    );
    expect((await repo.loadCached())!.updatedAt.day, 21);
    expect((await repo.refresh()).updatedAt.day, 22);
    final reopened = FeedRepository(
      feedUrl: _url,
      preferences: prefs,
      assetBundle: _Bundle(_feed()),
    );
    expect((await reopened.loadCached())!.updatedAt.day, 22);
    reopened.dispose();
  });

  test('retains cache after a failed fetch and after invalid JSON', () async {
    final prefs = await SharedPreferences.getInstance();
    var response = http.Response(jsonEncode(_feed(day: 22)), 200);
    final repo = FeedRepository(
      feedUrl: _url,
      preferences: prefs,
      assetBundle: _Bundle(_feed()),
      client: MockClient((_) async => response),
    );
    await repo.refresh();
    final saved = prefs.getKeys().map(prefs.getString).single;
    response = http.Response('Unavailable', 503);
    await expectLater(repo.refresh(), throwsA(isA<FeedException>()));
    expect((await repo.loadCached())!.updatedAt.day, 22);
    response = http.Response('<html>Not a feed</html>', 200);
    await expectLater(repo.refresh(), throwsA(isA<FeedException>()));
    expect(prefs.getKeys().map(prefs.getString).single, saved);
  });

  test('does not replace new cache with a stale response', () async {
    final prefs = await SharedPreferences.getInstance();
    var day = 23;
    final repo = FeedRepository(
      feedUrl: _url,
      preferences: prefs,
      assetBundle: _Bundle(_feed()),
      client: MockClient(
          (_) async => http.Response(jsonEncode(_feed(day: day)), 200)),
    );
    await repo.refresh();
    day = 22;
    await expectLater(
      repo.refresh(),
      throwsA(isA<FeedException>()
          .having((e) => e.message, 'message', contains('eski'))),
    );
    expect((await repo.loadCached())!.updatedAt.day, 23);
    final reopened = FeedRepository(
      feedUrl: _url,
      preferences: prefs,
      assetBundle: _Bundle(_feed()),
    );
    expect((await reopened.loadCached())!.updatedAt.day, 23);
    reopened.dispose();
  });

  test('coalesces concurrent refreshes into one request', () async {
    var requests = 0;
    final response = Completer<http.Response>();
    final repo = FeedRepository(
      feedUrl: _url,
      assetBundle: _Bundle(_feed()),
      client: MockClient((_) {
        requests++;
        return response.future;
      }),
    );
    final first = repo.refresh();
    final second = repo.refresh();
    response.complete(http.Response(jsonEncode(_feed(day: 22)), 200));
    expect(await first, same(await second));
    expect(requests, 1);
  });

  test('rejects unsafe endpoints before making any network request', () async {
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    });
    for (final url in [
      'http://example.com/feed.json',
      'not a url',
      'https://localhost/feed.json',
      'https://127.0.0.1/feed.json',
      'https://user:secret@example.com/feed.json',
    ]) {
      final repo = FeedRepository(feedUrl: url, client: client);
      await expectLater(repo.refresh(), throwsA(isA<FeedException>()));
    }
    expect(requests, 0);
  });

  test('timeout produces a useful Turkish error and keeps bundled data',
      () async {
    final response = Completer<http.Response>();
    final repo = FeedRepository(
      feedUrl: _url,
      timeout: const Duration(milliseconds: 10),
      assetBundle: _Bundle(_feed()),
      client: MockClient((_) => response.future),
    );
    await expectLater(
      repo.refresh(),
      throwsA(isA<FeedException>()
          .having((e) => e.message, 'message', contains('zamanında'))),
    );
    expect((await repo.loadCached())!.updatedAt.day, 21);
    response.complete(http.Response('{}', 200));
  });

  group('public YouTube data', () {
    test('all four channels contain precisely their ten newest videos',
        () async {
      final prefs = await SharedPreferences.getInstance();
      final requests = <String>[];
      final repo = FeedRepository(
        preferences: prefs,
        assetBundle: _Bundle(_feed()),
        client: MockClient((request) async {
          requests.add(request.url.toString());
          expect(
            request.followRedirects,
            request.url.path == '/feeds/videos.xml' ? isFalse : isTrue,
          );
          if (request.url.path == '/feeds/videos.xml') {
            return http.Response(
              _rss(request.url.queryParameters['channel_id']!),
              200,
              headers: {'content-type': 'application/atom+xml; charset=utf-8'},
            );
          }
          return http.Response(_about(request.url.pathSegments[1]), 200);
        }),
      );
      final fresh = await repo.refresh();
      expect(requests, hasLength(8));
      expect(fresh.channels, hasLength(4));
      for (var index = 0; index < fresh.channels.length; index++) {
        final channel = fresh.channels[index];
        expect(channel.id, 'channel$index');
        expect(channel.error, isNull);
        expect(channel.videos.map((video) => video.id),
            List.generate(10, (index) => 'video${14 - index}'));
        expect(channel.videos.first.title, 'Türkçe & video 14');
        expect(channel.videos.first.viewCount, 140);
        expect(channel.viewCount, 12345);
        expect(channel.subscriberCount, 9);
        expect(channel.videoCount, 123);
      }
      final reopened = FeedRepository(
        preferences: prefs,
        assetBundle: _Bundle(_feed()),
      );
      expect((await reopened.loadCached())!.toJson(), fresh.toJson());
      reopened.dispose();
    });

    test('accepts the real UC-less root ID only with a matching channel link',
        () {
      final previous = Feed.fromJson(_feed()).channels.first;
      final channel = ChannelStats.fromJson({
        ...previous.toJson(),
        'id': 'UCexample',
      });
      final rss = _rss(channel.id, shortenedRoot: true);
      expect(
        parseYouTubeFeed(rss, previous: channel, checkedAt: DateTime.utc(2026)),
        isA<ChannelStats>(),
      );
      expect(
        () => parseYouTubeFeed(
          rss.replaceFirst('/channel/UCexample', '/channel/UCother'),
          previous: channel,
          checkedAt: DateTime.utc(2026),
        ),
        throwsA(isA<FeedException>()),
      );
      expect(
        () => parseYouTubeFeed(
          _rss(channel.id, entryChannelId: 'UCother'),
          previous: channel,
          checkedAt: DateTime.utc(2026),
        ),
        throwsA(isA<FeedException>()),
      );
    });

    test(
        'preserves zero views and never replaces absent or invalid counts with zero',
        () {
      final previous = Feed.fromJson(_feed()).channels.first;
      final rss = _rss(previous.id, count: 4)
          .replaceFirst('views="10"', 'views="invalid"')
          .replaceFirst('views="20"', 'views="-1"')
          .replaceFirst('<media:statistics views="30"/>', '');
      final result = parseYouTubeFeed(
        rss,
        previous: previous,
        checkedAt: DateTime.utc(2026),
      );
      expect(
          result.videos.map((video) => video.viewCount), [null, null, null, 0]);
      expect(result.videos.every((video) => video.likeCount == null), isTrue);
      expect(result.viewCount, isNull);
      expect(result.subscriberCount, isNull);
    });

    test('partial RSS failure preserves the affected channel and its timestamp',
        () async {
      final previous = Feed.fromJson(_feed());
      final repo = FeedRepository(
        assetBundle: _Bundle(previous.toJson()),
        client: MockClient((request) async {
          if (request.url.path != '/feeds/videos.xml') {
            return http.Response('About unavailable', 503);
          }
          final id = request.url.queryParameters['channel_id']!;
          return id == 'channel2'
              ? http.Response('Temporary failure', 503)
              : http.Response(_rss(id), 200);
        }),
      );
      final fresh = await repo.refresh();
      expect(fresh.channels, hasLength(4));
      final failed = fresh.channels[2];
      expect(failed.error, contains('503'));
      expect({...failed.toJson(), 'error': null},
          {...previous.channels[2].toJson(), 'error': null});
      expect(fresh.channels[0].videos, hasLength(10));
      expect(fresh.channels[0].error, isNull);
      // About-page failure must not block current video statistics or pass old
      // channel totals off as newly retrieved observations.
      expect(fresh.channels[0].viewCount, isNull);
    });

    test('all-channel failure leaves both memory and persistent cache intact',
        () async {
      final prefs = await SharedPreferences.getInstance();
      var fail = false;
      final repo = FeedRepository(
        preferences: prefs,
        assetBundle: _Bundle(_feed()),
        client: MockClient((request) async {
          if (fail) return http.Response('Unavailable', 503);
          return http.Response(
            request.url.path == '/feeds/videos.xml'
                ? _rss(request.url.queryParameters['channel_id']!)
                : _about(request.url.pathSegments[1]),
            200,
          );
        }),
      );
      final good = await repo.refresh();
      final saved = prefs.getKeys().map(prefs.getString).single;
      fail = true;
      await expectLater(repo.refresh(), throwsA(isA<FeedException>()));
      expect((await repo.loadCached())!.toJson(), good.toJson());
      expect(prefs.getKeys().map(prefs.getString).single, saved);
    });

    test('no bundle still refreshes the four configured real channels',
        () async {
      final ids = <String>[];
      final repo = FeedRepository(
        assetBundle: _MissingBundle(),
        client: MockClient((request) async {
          if (request.url.path != '/feeds/videos.xml') {
            return http.Response('', 503);
          }
          final id = request.url.queryParameters['channel_id']!;
          ids.add(id);
          return http.Response(_rss(id, shortenedRoot: true), 200);
        }),
      );
      final fresh = await repo.refresh();
      expect(ids.toSet(), {
        'UCU-N6tFV2_YVElMaB0YXPrQ',
        'UCGaV2Xk_1mFavFlCkdUOgAQ',
        'UCxRqfXR2BmK-TBHh77SlTEw',
        'UCMVToyerFF_UxUP0k_2GAPQ',
      });
      expect(fresh.channels[2].handle, '@globalhaber-g7k');
      expect(fresh.channels.every((channel) => channel.videos.length == 10),
          isTrue);
    });

    test('rejects malformed XML, wrong channels and duplicate video IDs', () {
      final previous = Feed.fromJson(_feed()).channels.first;
      for (final source in [
        '<html>unavailable</html>',
        '<feed><broken',
        _rss('other'),
        _rss(previous.id).replaceAll('video1<', 'video0<'),
      ]) {
        expect(
          () => parseYouTubeFeed(
            source,
            previous: previous,
            checkedAt: DateTime.utc(2026),
          ),
          throwsA(isA<FeedException>()),
        );
      }
    });

    test('reads exact about-model counts including hex-escaped mobile pages',
        () {
      final about = _about('channel0');
      final hexEscaped = about
          .replaceAll('"', r'\x22')
          .replaceAll('{', r'\x7b')
          .replaceAll('}', r'\x7d');
      for (final source in [about, hexEscaped]) {
        expect(parseYouTubeAbout(source, channelId: 'channel0'), {
          'subscriberCount': 9,
          'viewCount': 12345,
          'videoCount': 123,
        });
      }
    });

    test('ignores unrelated, rounded, malformed and wrong-channel counts', () {
      final rounded = jsonEncode({
        'viewCountText': '999999 views',
        'aboutChannelViewModel': {
          'channelId': 'channel0',
          'subscriberCountText': '1.2K subscribers',
          'viewCountText': '12,34 views',
          'videoCountText': '9 subscribers',
        },
      });
      for (final source in [null, '', rounded, _about('other')]) {
        expect(parseYouTubeAbout(source, channelId: 'channel0').values,
            everyElement(isNull));
      }
      expect(parseYouTubeAbout(_about('channel0', zero: true)), {
        'subscriberCount': 0,
        'viewCount': 0,
        'videoCount': 0,
      });
    });
  });
}

const _url = 'https://raw.githubusercontent.com/example/repo/main/feed.json';

Map<String, dynamic> _video(int index, {int? views = 12}) => {
      'id': 'video$index',
      'title': 'Video $index',
      'viewCount': views,
      'publishedAt': DateTime.utc(2026, 9, index + 1).toIso8601String(),
      'thumbnail': 'https://i.ytimg.com/vi/video$index/mqdefault.jpg',
      'url': 'https://www.youtube.com/shorts/video$index',
    };

Map<String, dynamic> _feed({int day = 21}) => {
      'schemaVersion': 1,
      'updatedAt': DateTime.utc(2026, 9, day).toIso8601String(),
      'channels': List.generate(
        4,
        (index) => <String, dynamic>{
          'id': 'channel$index',
          'title': 'Kanal $index',
          'handle': '@channel$index',
          'repository': 'example/repo$index',
          'url': 'https://www.youtube.com/channel/channel$index',
          'subscriberCount': 20,
          'viewCount': 500,
          'videoCount': 12,
          'updatedAt': DateTime.utc(2026, 9, day).toIso8601String(),
          'videos': [_video(0)],
        },
      ),
    };

class _Bundle extends CachingAssetBundle {
  _Bundle(this.feed);
  final Map<String, dynamic> feed;

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(jsonEncode(feed))));
}

class _MissingBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      throw StateError('No bundled feed');
}

String _rss(
  String id, {
  int count = 15,
  bool shortenedRoot = false,
  String? entryChannelId,
}) =>
    '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:yt="http://www.youtube.com/xml/schemas/2015"
      xmlns:media="http://search.yahoo.com/mrss/">
  <yt:channelId>${shortenedRoot ? id.substring(2) : id}</yt:channelId>
  <title>Güncel kanal</title>
  <link rel="alternate" href="https://www.youtube.com/channel/$id"/>
  ${List.generate(count, (index) => '''
  <entry>
    <yt:videoId>video$index</yt:videoId>
    <yt:channelId>${entryChannelId ?? id}</yt:channelId>
    <title>Türkçe &amp; video $index</title>
    <published>${DateTime.utc(2026, 9, index + 1).toIso8601String()}</published>
    <media:group>
      <media:thumbnail url="https://i.ytimg.com/vi/video$index/hqdefault.jpg"/>
      <media:community><media:statistics views="${index * 10}"/></media:community>
    </media:group>
  </entry>''').join()}
</feed>''';

String _about(String id, {bool zero = false}) => jsonEncode({
      'unrelated': {'viewCountText': '999999 views'},
      'aboutChannelViewModel': {
        'channelId': id,
        'subscriberCountText': '${zero ? 0 : 9} subscribers',
        'viewCountText': '${zero ? '0' : '12,345'} views',
        'videoCountText': '${zero ? 0 : 123} videos',
      },
    });
