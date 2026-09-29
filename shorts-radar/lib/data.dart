import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

/// Missing counts remain null: unavailable statistics are never shown as zero.
class VideoStats {
  const VideoStats({
    required this.id,
    required this.title,
    this.viewCount,
    this.likeCount,
    this.commentCount,
    required this.publishedAt,
    required this.thumbnail,
    required this.url,
    this.durationSeconds,
  });

  final String id;
  final String title;
  final int? viewCount;
  final int? likeCount;
  final int? commentCount;
  final DateTime publishedAt;
  final String thumbnail;
  final String url;
  final int? durationSeconds;

  factory VideoStats.fromJson(Map<String, dynamic> json) => VideoStats(
        id: _text(json, 'id'),
        title: _text(json, 'title'),
        viewCount: _count(json, 'viewCount'),
        likeCount: _count(json, 'likeCount'),
        commentCount: _count(json, 'commentCount'),
        publishedAt: _date(json, 'publishedAt'),
        thumbnail: _optionalHttpsUrl(json, 'thumbnail') ?? '',
        url: _httpsUrl(json, 'url'),
        durationSeconds: _count(json, 'durationSeconds'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'viewCount': viewCount,
        'likeCount': likeCount,
        'commentCount': commentCount,
        'publishedAt': publishedAt.toUtc().toIso8601String(),
        'thumbnail': thumbnail.isEmpty ? null : thumbnail,
        'url': url,
        'durationSeconds': durationSeconds,
      };
}

class ChannelStats {
  const ChannelStats({
    required this.id,
    required this.title,
    required this.handle,
    required this.repository,
    required this.url,
    this.thumbnail,
    this.subscriberCount,
    this.viewCount,
    this.videoCount,
    required this.updatedAt,
    this.error,
    required this.videos,
  });

  final String id;
  final String title;
  final String handle;
  final String repository;
  final String url;
  final String? thumbnail;
  final int? subscriberCount;
  final int? viewCount;
  final int? videoCount;
  final DateTime updatedAt;
  final String? error;
  final List<VideoStats> videos;

  factory ChannelStats.fromJson(Map<String, dynamic> json) {
    final rawVideos = json['videos'];
    if (rawVideos is! List) {
      throw const FeedException('Kanalın video listesi okunamadı.');
    }
    final videos = rawVideos
        .map((value) => VideoStats.fromJson(_object(value)))
        .toList()
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    if (videos.map((video) => video.id).toSet().length != videos.length) {
      throw const FeedException('Veri kaynağında yinelenen videolar var.');
    }
    return ChannelStats(
      id: _text(json, 'id'),
      title: _text(json, 'title'),
      handle: _text(json, 'handle', allowEmpty: true),
      repository: _text(json, 'repository', allowEmpty: true),
      url: _httpsUrl(json, 'url'),
      thumbnail: _optionalHttpsUrl(json, 'thumbnail'),
      subscriberCount: _count(json, 'subscriberCount'),
      viewCount: _count(json, 'viewCount'),
      videoCount: _count(json, 'videoCount'),
      updatedAt: _date(json, 'updatedAt'),
      error: _optionalText(json, 'error'),
      videos: List.unmodifiable(videos.take(10)),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'handle': handle,
        'repository': repository,
        'url': url,
        'thumbnail': thumbnail,
        'subscriberCount': subscriberCount,
        'viewCount': viewCount,
        'videoCount': videoCount,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'error': error,
        'videos': videos.map((video) => video.toJson()).toList(),
      };
}

class Feed {
  const Feed({
    this.schemaVersion = 1,
    required this.updatedAt,
    required this.channels,
  });

  final int schemaVersion;
  final DateTime updatedAt;
  final List<ChannelStats> channels;

  factory Feed.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FeedException(
        'Bu veri sürümü desteklenmiyor. Uygulamayı güncelleyin.',
      );
    }
    final rawChannels = json['channels'];
    if (rawChannels is! List || rawChannels.length != 4) {
      throw const FeedException('Veri kaynağı tam olarak 4 kanal içermeli.');
    }
    final channels = rawChannels
        .map((value) => ChannelStats.fromJson(_object(value)))
        .toList();
    if (channels.map((channel) => channel.id).toSet().length != 4) {
      throw const FeedException('Veri kaynağında yinelenen kanallar var.');
    }
    return Feed(
      updatedAt: _date(json, 'updatedAt'),
      channels: List.unmodifiable(channels),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'channels': channels.map((channel) => channel.toJson()).toList(),
      };
}

class FeedException implements Exception {
  const FeedException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Fetches only a public feed; no YouTube or GitHub credential lives in the app.
class FeedRepository {
  FeedRepository({
    this.feedUrl,
    http.Client? client,
    SharedPreferences? preferences,
    AssetBundle? assetBundle,
    this.timeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _preferences = preferences,
        _assetBundle = assetBundle ?? rootBundle;

  /// Optional public JSON source. Defaults to the four channels' YouTube feeds.
  final String? feedUrl;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;
  final SharedPreferences? _preferences;
  final AssetBundle _assetBundle;
  Feed? _latest;
  Future<Feed>? _refreshing;

  String get _cacheKey => 'shorts_radar.feed.v1.${feedUrl ?? 'youtube-rss'}';

  Future<SharedPreferences> get _prefs async =>
      _preferences ?? await SharedPreferences.getInstance();

  /// Falls back to the bundled snapshot when no usable local cache exists.
  Future<Feed?> loadCached() async {
    if (_latest != null) return _latest;
    Feed? candidate;
    try {
      final stored = (await _prefs).getString(_cacheKey);
      if (stored != null) candidate = _decode(stored);
    } catch (_) {
      // A corrupt local file must not prevent bundled or network data loading.
    }
    try {
      final bundled = _decode(
        await _assetBundle.loadString('assets/initial_feed.json'),
      );
      if (candidate == null || bundled.updatedAt.isAfter(candidate.updatedAt)) {
        candidate = bundled;
      }
    } catch (_) {
      // A first launch can still refresh if no bundled snapshot is available.
    }
    // A concurrent network refresh may have already obtained newer data.
    if (candidate != null &&
        (_latest == null || candidate.updatedAt.isAfter(_latest!.updatedAt))) {
      _latest = candidate;
    }
    return _latest;
  }

  /// Coalesces simultaneous refreshes and never replaces a newer snapshot.
  Future<Feed> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<Feed> _refresh() async {
    if (feedUrl == null) return _refreshYouTube();
    final uri = Uri.tryParse(feedUrl!);
    if (uri == null || !_isPublicHttps(uri)) {
      throw const FeedException(
        'Veri kaynağı geçerli ve herkese açık bir HTTPS adresi olmalı.',
      );
    }
    final previous = await loadCached();
    late http.Response response;
    try {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers['Accept'] = 'application/json';
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
    } on TimeoutException {
      throw const FeedException(
        'Veri kaynağı zamanında yanıt vermedi. Yeniden deneyin.',
      );
    } on http.ClientException {
      throw const FeedException(
        'Veri kaynağına ulaşılamadı. İnternet bağlantınızı kontrol edin.',
      );
    }
    if (response.statusCode != 200) {
      throw FeedException(
        'Veri kaynağı yanıt vermedi (HTTP ${response.statusCode}). '
        'Son kaydedilen veriler korunuyor.',
      );
    }
    if (response.bodyBytes.length > 2 * 1024 * 1024) {
      throw const FeedException('Veri kaynağının yanıtı beklenenden büyük.');
    }
    final fresh =
        _decode(utf8.decode(response.bodyBytes, allowMalformed: true));
    final current = _latest ?? previous;
    if (current != null && fresh.updatedAt.isBefore(current.updatedAt)) {
      throw const FeedException(
        'Veri kaynağı daha eski bir kayıt döndürdü. '
        'Son kaydedilen veriler korunuyor.',
      );
    }
    return _save(fresh);
  }

  Future<Feed> _refreshYouTube() async {
    final previous = await loadCached();
    final channels = previous?.channels ?? _configuredChannels();
    final refreshed = await Future.wait(channels.map(_refreshChannel));
    if (refreshed.every((channel) => channel.error != null)) {
      throw const FeedException(
        'YouTube kanallarına ulaşılamadı. İnternet bağlantınızı kontrol edin. '
        'Son kaydedilen veriler korunuyor.',
      );
    }
    return _save(Feed(updatedAt: DateTime.now().toUtc(), channels: refreshed));
  }

  Future<ChannelStats> _refreshChannel(ChannelStats previous) async {
    try {
      final rssUri = Uri.https('www.youtube.com', '/feeds/videos.xml', {
        'channel_id': previous.id,
      });
      final aboutUri =
          Uri.https('www.youtube.com', '/channel/${previous.id}/about', {
        'hl': 'en',
      });
      // The about page is supplementary: its absence never hides video counts.
      final aboutFuture =
          _getText(aboutUri, accept: 'text/html', followRedirects: true)
              .then<String?>((value) => value)
              .catchError((Object _) => null);
      final rss = await _getText(rssUri, accept: 'application/atom+xml');
      final about = await aboutFuture;
      return parseYouTubeFeed(
        rss,
        previous: previous,
        checkedAt: DateTime.now().toUtc(),
        aboutHtml: about,
      );
    } catch (error) {
      return ChannelStats.fromJson({
        ...previous.toJson(),
        'error': error is FeedException
            ? error.message
            : 'Kanalın güncel verileri okunamadı. Son kayıt gösteriliyor.',
      });
    }
  }

  Future<String> _getText(
    Uri uri, {
    required String accept,
    bool followRedirects = false,
  }) async {
    try {
      final request = http.Request('GET', uri)
        // YouTube routes /channel/.../about to the public canonical URL.
        // Only that URI, generated from a fixed channel ID, follows redirects.
        ..followRedirects = followRedirects
        ..maxRedirects = followRedirects ? 3 : 5
        ..headers.addAll({
          'Accept': accept,
          'Accept-Language': 'en-US,en;q=0.9',
          'Cache-Control': 'no-cache',
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13) '
              'AppleWebKit/537.36 (KHTML, like Gecko) '
              'Chrome/120.0.0.0 Mobile Safari/537.36',
        });
      final response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw FeedException(
          'YouTube yanıt vermedi (HTTP ${response.statusCode}). '
          'Son kayıt gösteriliyor.',
        );
      }
      if (response.bodyBytes.length > 6 * 1024 * 1024) {
        throw const FeedException('YouTube yanıtı beklenenden büyük.');
      }
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } on TimeoutException {
      throw const FeedException(
          'YouTube zamanında yanıt vermedi. Son kayıt gösteriliyor.');
    } on http.ClientException {
      throw const FeedException(
          'YouTube bağlantısı kurulamadı. Son kayıt gösteriliyor.');
    }
  }

  Future<Feed> _save(Feed fresh) async {
    // Only validated, current data may enter the persistent cache.
    try {
      await (await _prefs).setString(_cacheKey, jsonEncode(fresh.toJson()));
    } catch (_) {
      // Network data is still useful if device storage is temporarily blocked.
    }
    _latest = fresh;
    return fresh;
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

const _atomNamespace = 'http://www.w3.org/2005/Atom';
const _youtubeNamespace = 'http://www.youtube.com/xml/schemas/2015';
const _mediaNamespace = 'http://search.yahoo.com/mrss/';

/// RSS view counts are public YouTube observations and can lag YouTube Studio.
/// [checkedAt] records retrieval time, not a claim of live analytics freshness.
ChannelStats parseYouTubeFeed(
  String source, {
  required ChannelStats previous,
  required DateTime checkedAt,
  String? aboutHtml,
}) {
  late XmlElement root;
  try {
    root = XmlDocument.parse(source).rootElement;
  } on XmlException {
    throw const FeedException(
        'YouTube video listesi okunamadı. Son kayıt gösteriliyor.');
  }
  final rootChannelId =
      root.getElement('channelId', namespace: _youtubeNamespace)?.innerText;
  // YouTube's current Atom feed omits "UC" from its top-level channelId,
  // while entry IDs and the canonical channel link retain the full ID.
  final fullIdMatches = rootChannelId == previous.id;
  final shortenedIdMatches = previous.id.startsWith('UC') &&
      rootChannelId == previous.id.substring(2) &&
      root.findElements('link', namespace: _atomNamespace).any((link) =>
          link.getAttribute('rel') == 'alternate' &&
          link.getAttribute('href') ==
              'https://www.youtube.com/channel/${previous.id}');
  if (root.name.local != 'feed' ||
      root.namespaceUri != _atomNamespace ||
      (!fullIdMatches && !shortenedIdMatches)) {
    throw const FeedException(
        'YouTube farklı veya geçersiz bir kanal döndürdü.');
  }
  final videos = <VideoStats>[];
  for (final entry in root.findElements('entry', namespace: _atomNamespace)) {
    final entryChannelId =
        entry.getElement('channelId', namespace: _youtubeNamespace)?.innerText;
    if (entryChannelId != null && entryChannelId != previous.id) {
      throw const FeedException(
          'YouTube farklı bir kanalın videosunu döndürdü.');
    }
    final id =
        entry.getElement('videoId', namespace: _youtubeNamespace)?.innerText;
    final title =
        entry.getElement('title', namespace: _atomNamespace)?.innerText;
    final published =
        entry.getElement('published', namespace: _atomNamespace)?.innerText;
    final group = entry.getElement('group', namespace: _mediaNamespace);
    final statistics = group
        ?.getElement('community', namespace: _mediaNamespace)
        ?.getElement('statistics', namespace: _mediaNamespace);
    final thumbnail = group
        ?.getElement('thumbnail', namespace: _mediaNamespace)
        ?.getAttribute('url');
    if (id == null || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw const FeedException('YouTube video kimliği okunamadı.');
    }
    videos.add(VideoStats.fromJson({
      'id': id,
      'title': title,
      'publishedAt': published,
      'thumbnail': thumbnail,
      'viewCount': _nonNegativeInt(statistics?.getAttribute('views')),
      'url': 'https://www.youtube.com/shorts/$id',
    }));
  }
  final metrics = parseYouTubeAbout(aboutHtml, channelId: previous.id);
  return ChannelStats.fromJson({
    ...previous.toJson(),
    'title': root.getElement('title', namespace: _atomNamespace)?.innerText ??
        previous.title,
    'updatedAt': checkedAt.toUtc().toIso8601String(),
    'subscriberCount': metrics['subscriberCount'],
    'viewCount': metrics['viewCount'],
    'videoCount': metrics['videoCount'],
    'error': null,
    'videos': videos.map((video) => video.toJson()).toList(),
  });
}

/// Only exact public counts are accepted; rounded "1.2K" counts stay unknown.
Map<String, int?> parseYouTubeAbout(String? source, {String? channelId}) {
  // Mobile pages contain JS hex-escaped JSON; decode characters, never execute
  // the page. Read only the channel's about model, not unrelated page counts.
  final text = (source ?? '').replaceAllMapped(
    RegExp(r'\\x([0-9a-fA-F]{2})'),
    (match) => String.fromCharCode(int.parse(match[1]!, radix: 16)),
  );
  final modelText = _aboutModelText(text, channelId);
  Map<String, dynamic>? model;
  for (final match
      in RegExp(r'"aboutChannelViewModel"\s*:\s*\{').allMatches(text)) {
    final candidate = _jsonObjectAt(text, match.end - 1);
    if (candidate != null &&
        (channelId == null || candidate['channelId'] == channelId)) {
      model = candidate;
      break;
    }
  }
  int? read(String key, String unit) {
    final value =
        _jsonStringValue(modelText ?? '', '${key}Text') ?? model?['${key}Text'];
    if (value is! String) return null;
    // Only full decimal values are usable as an exact count.
    final number = RegExp(
      '^([0-9]+|[1-9][0-9]{0,2}(?:,[0-9]{3})+)\\s+$unit\$',
    ).firstMatch(value.trim());
    /*
      '^([0-9]+|[1-9][0-9]{0,2}(?:,[0-9]{3})+)\s+$unit$',
    ).firstMatch(value.trim());
    */
    return _nonNegativeInt(number?.group(1)?.replaceAll(',', ''));
  }

  return {
    'subscriberCount': read('subscriberCount', 'subscribers?'),
    'viewCount': read('viewCount', 'views?'),
    'videoCount': read('videoCount', 'videos?'),
  };
}

/// Isolates a channel's own about model before reading any public counts.
/// It intentionally does not evaluate YouTube's JavaScript.
String? _aboutModelText(String text, String? expectedChannelId) {
  const marker = '"aboutChannelViewModel":{';
  var searchFrom = 0;
  while (true) {
    final start = text.indexOf(marker, searchFrom);
    if (start < 0) return null;
    final next = text.indexOf(marker, start + marker.length);
    final end = next < 0 ? text.length : next;
    final candidate = text.substring(start, end);
    final candidateId = _jsonStringValue(candidate, 'channelId');
    if (expectedChannelId == null || candidateId == expectedChannelId) {
      return candidate;
    }
    searchFrom = start + marker.length;
  }
}

String? _jsonStringValue(String source, String key) {
  final marker = '"$key":"';
  final start = source.indexOf(marker);
  if (start < 0) return null;
  final valueStart = start + marker.length;
  final valueEnd = source.indexOf('"', valueStart);
  if (valueEnd < 0) return null;
  return source.substring(valueStart, valueEnd);
}

Map<String, dynamic>? _jsonObjectAt(String text, int start) {
  var depth = 0;
  var quoted = false;
  var escaped = false;
  for (var index = start; index < text.length; index++) {
    final character = text[index];
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (character == r'\') {
        escaped = true;
      } else if (character == '"') {
        quoted = false;
      }
    } else if (character == '"') {
      quoted = true;
    } else if (character == '{') {
      depth++;
    } else if (character == '}' && --depth == 0) {
      try {
        final result = jsonDecode(text.substring(start, index + 1));
        return result is Map<String, dynamic> ? result : null;
      } on FormatException {
        return null;
      }
    }
  }
  return null;
}

int? _nonNegativeInt(String? source) {
  final value = source == null ? null : int.tryParse(source);
  return value != null && value >= 0 ? value : null;
}

List<ChannelStats> _configuredChannels() {
  const definitions = [
    ['UCU-N6tFV2_YVElMaB0YXPrQ', 'ilginçgerçekler', '@ilgiçekici15', 'denede'],
    [
      'UCGaV2Xk_1mFavFlCkdUOgAQ',
      'türkiyedenhaber',
      '@türkiyedenhaber-v9e',
      'Haberdenede'
    ],
    [
      'UCxRqfXR2BmK-TBHh77SlTEw',
      'globalhaber',
      '@globalhaber-g7k',
      'Globalhaberdenede'
    ],
    ['UCMVToyerFF_UxUP0k_2GAPQ', 'zekanıtestet', '@zekanıtestet', 'Quizdenede'],
  ];
  return definitions
      .map((row) => ChannelStats(
            id: row[0],
            title: row[1],
            handle: row[2],
            repository: 'chaoslightnight2-ctrl/${row[3]}',
            url: 'https://www.youtube.com/channel/${row[0]}',
            updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            videos: const [],
          ))
      .toList();
}

Feed _decode(String source) {
  try {
    return Feed.fromJson(_object(jsonDecode(source)));
  } on FormatException {
    throw const FeedException('Veri kaynağı geçerli bir JSON dosyası değil.');
  }
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FeedException('Veri kaynağının biçimi okunamadı.');
  }
  return value;
}

String _text(Map<String, dynamic> json, String key, {bool allowEmpty = false}) {
  final value = json[key];
  if (value is! String || (!allowEmpty && value.trim().isEmpty)) {
    throw FeedException('Veri kaynağında "$key" alanı eksik veya geçersiz.');
  }
  return value;
}

String? _optionalText(Map<String, dynamic> json, String key) {
  if (json[key] == null) return null;
  return _text(json, key, allowEmpty: true);
}

int? _count(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! int || value < 0) {
    throw FeedException('Veri kaynağında "$key" sayısı geçersiz.');
  }
  return value;
}

DateTime _date(Map<String, dynamic> json, String key) {
  final value = _text(json, key);
  final date = DateTime.tryParse(value);
  if (date == null ||
      !value.contains('T') ||
      !RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(value)) {
    throw FeedException('Veri kaynağında "$key" tarihi geçersiz.');
  }
  return date.toUtc();
}

String _httpsUrl(Map<String, dynamic> json, String key) {
  final value = _text(json, key);
  final uri = Uri.tryParse(value);
  if (uri == null || !_isPublicHttps(uri)) {
    throw FeedException('Veri kaynağında "$key" bağlantısı geçersiz.');
  }
  return value;
}

String? _optionalHttpsUrl(Map<String, dynamic> json, String key) {
  if (json[key] == null || json[key] == '') return null;
  return _httpsUrl(json, key);
}

bool _isPublicHttps(Uri uri) {
  if (uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      (uri.hasPort && uri.port != 443)) {
    return false;
  }
  final host = uri.host.toLowerCase();
  if (host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.contains(':') ||
      !host.contains('.')) {
    return false;
  }
  final parts = host.split('.');
  if (parts.length == 4 && parts.every((part) => int.tryParse(part) != null)) {
    // The public JSON source should have a DNS name, not a private IP literal.
    return false;
  }
  return RegExp(r'^[a-z0-9][a-z0-9.-]*[a-z0-9]$').hasMatch(host);
}
