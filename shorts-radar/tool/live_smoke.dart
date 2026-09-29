// Run explicitly with: flutter test tool/live_smoke.dart --reporter expanded
// This opt-in check makes real public YouTube requests. Only device preferences
// are in-memory; HTTP and the shipped parsing/repository code are unchanged.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shorts_radar/data.dart';
import 'package:xml/xml.dart';

void main() {
  _LiveNetworkBinding();
  test(
      'retrieves four real channels and their exact latest ten RSS observations',
      () async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final client = _RecordingClient();
    final repo = FeedRepository(
      client: client,
      assetBundle: _FileBundle(),
      timeout: const Duration(seconds: 35),
    );
    addTearDown(client.close);
    final fresh = await repo.refresh();
    expect(fresh.channels.map((channel) => channel.id).toSet(), {
      'UCU-N6tFV2_YVElMaB0YXPrQ',
      'UCGaV2Xk_1mFavFlCkdUOgAQ',
      'UCxRqfXR2BmK-TBHh77SlTEw',
      'UCMVToyerFF_UxUP0k_2GAPQ',
    });
    final evidence = Directory('../live-data-review')
      ..createSync(recursive: true);
    for (final channel in fresh.channels) {
      expect(channel.error, isNull, reason: '${channel.id}: ${channel.error}');
      expect(channel.videos, hasLength(10), reason: channel.id);
      final rssUri = Uri.https('www.youtube.com', '/feeds/videos.xml', {
        'channel_id': channel.id,
      });
      final rss = client.responses[rssUri.toString()]!;
      expect(rss.statusCode, 200);
      final rawEntries = XmlDocument.parse(utf8.decode(rss.bodyBytes))
          .rootElement
          .findElements('entry', namespace: 'http://www.w3.org/2005/Atom')
          .toList()
        ..sort((a, b) => DateTime.parse(b.getElement('published')!.innerText)
            .compareTo(DateTime.parse(a.getElement('published')!.innerText)));
      expect(rawEntries.length, greaterThanOrEqualTo(10));
      for (var index = 0; index < 10; index++) {
        final raw = rawEntries[index];
        final id = raw
            .getElement('videoId',
                namespace: 'http://www.youtube.com/xml/schemas/2015')!
            .innerText;
        final views = raw
            .findAllElements('statistics',
                namespace: 'http://search.yahoo.com/mrss/')
            .first
            .getAttribute('views')!;
        expect(channel.videos[index].id, id);
        expect(channel.videos[index].viewCount, int.parse(views));
      }
      expect(channel.subscriberCount, isNotNull, reason: channel.id);
      expect(channel.viewCount, isNotNull, reason: channel.id);
      expect(channel.videoCount, isNotNull, reason: channel.id);
      File('${evidence.path}/dart-${channel.id}.rss')
          .writeAsBytesSync(rss.bodyBytes);
      // ignore: avoid_print
      print('${channel.handle}: ${channel.videos.length} videos; '
          'views=${channel.videos.map((video) => video.viewCount).join(',')}; '
          'channelViews=${channel.viewCount}; subscribers=${channel.subscriberCount}');
    }
    final reopened = FeedRepository(assetBundle: _FileBundle());
    addTearDown(reopened.dispose);
    expect((await reopened.loadCached())!.toJson(), fresh.toJson());
    File('${evidence.path}/dart-live-feed.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(fresh.toJson()));
  }, timeout: const Timeout(Duration(minutes: 2)));
}

class _LiveNetworkBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}

class _RecordingClient extends http.BaseClient {
  final _inner = http.Client();
  final responses = <String, http.Response>{};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await http.Response.fromStream(await _inner.send(request));
    responses[request.url.toString()] = response;
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }

  @override
  void close() => _inner.close();
}
