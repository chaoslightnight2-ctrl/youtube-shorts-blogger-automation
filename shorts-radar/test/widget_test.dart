import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shorts_radar/data.dart';
import 'package:shorts_radar/main.dart';

/// Exercises the real interface with the bundled public YouTube observation.
/// Network and storage are isolated so these tests make no freshness claim.
class _FixtureRepository extends FeedRepository {
  _FixtureRepository(this.cached) : next = cached;

  final Feed cached;
  Feed next;
  FeedException? failure;
  int refreshCalls = 0;

  @override
  Future<Feed?> loadCached() async => cached;

  @override
  Future<Feed> refresh() async {
    refreshCalls++;
    if (failure != null) throw failure!;
    return next;
  }
}

void main() {
  late Feed fixture;

  setUpAll(() {
    fixture = Feed.fromJson(
      jsonDecode(File('assets/initial_feed.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    expect(fixture.channels, hasLength(4));
    for (final channel in fixture.channels) {
      expect(channel.videos, hasLength(10));
    }
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> launch(
    WidgetTester tester,
    _FixtureRepository repository, {
    Size size = const Size(360, 800),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(repository.dispose);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(ShortsRadarApp(repository: repository));
    await tester.pumpAndSettle();
    expect(repository.refreshCalls, 1);
    expect(tester.takeException(), isNull);
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Finder thumbnailFor(VideoStats video) => find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is NetworkImage &&
            (widget.image as NetworkImage).url == video.thumbnail,
      );

  Future<void> checkVideo(
    WidgetTester tester,
    VideoStats video,
    int rank, {
    Finder? scrollable,
  }) async {
    // Titles can repeat on the real channels; each thumbnail identifies an ID.
    final thumbnail = thumbnailFor(video).last;
    await tester.scrollUntilVisible(
      thumbnail,
      260,
      scrollable: scrollable ?? find.byType(Scrollable).last,
      maxScrolls: 80,
    );
    await tester.pumpAndSettle();
    final card =
        find.ancestor(of: thumbnail, matching: find.byType(InkWell)).first;
    expect(find.descendant(of: card, matching: find.text(video.title)),
        findsOneWidget);
    expect(
        find.descendant(of: card, matching: find.text(number(video.viewCount))),
        findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('#$rank')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  testWidgets(
      'overview opens all four channels with ten individual view counts',
      (tester) async {
    await launch(tester, _FixtureRepository(fixture));
    expect(find.text('4 kanal · 40 video'), findsOneWidget);
    final total = fixture.channels
        .expand((c) => c.videos)
        .fold<int>(0, (sum, v) => sum + (v.viewCount ?? 0));
    expect(find.text(number(total)), findsWidgets);

    for (final channel in fixture.channels) {
      await tester.scrollUntilVisible(find.text(channel.title), 250,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(channel.title));
      await tester.pumpAndSettle();
      final sheet = find.byType(DraggableScrollableSheet);
      expect(sheet, findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text(channel.handle)),
          findsOneWidget);
      for (final label in ['Abone', 'Kanal izlenmesi', 'Toplam video']) {
        expect(find.descendant(of: sheet, matching: find.text(label)),
            findsOneWidget);
      }
      for (var index = 0; index < channel.videos.length; index++) {
        await checkVideo(tester, channel.videos[index], index + 1);
      }
      Navigator.of(tester.element(sheet)).pop();
      await tester.pumpAndSettle();
    }
    await disposeApp(tester);
  });

  testWidgets('video library renders every one of the four channels latest ten',
      (tester) async {
    await launch(tester, _FixtureRepository(fixture));
    await tester.tap(find.byIcon(Icons.video_library_outlined).last);
    await tester.pumpAndSettle();
    expect(find.text('Video kütüphanesi'), findsOneWidget);
    for (final channel in fixture.channels) {
      await tester.scrollUntilVisible(find.text(channel.title), 250,
          scrollable: find.byType(Scrollable).first, maxScrolls: 80);
      expect(find.text(channel.title), findsOneWidget);
      for (var index = 0; index < channel.videos.length; index++) {
        await checkVideo(tester, channel.videos[index], index + 1);
      }
    }
    await disposeApp(tester);
  });

  testWidgets(
      'small screen with larger text keeps the entire dashboard usable',
      (tester) async {
    await launch(tester, _FixtureRepository(fixture),
        size: const Size(320, 700), textScale: 1.4);
    for (final channel in fixture.channels) {
      await tester.scrollUntilVisible(find.text(channel.title), 220,
          scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
    }
    await disposeApp(tester);
  });

  testWidgets('refresh compares against stored views and survives app restart',
      (tester) async {
    final repository = _FixtureRepository(fixture);
    await launch(tester, repository);
    // Only this refresh scenario changes a count; it is not a live observation.
    final json = fixture.toJson();
    json['updatedAt'] =
        fixture.updatedAt.add(const Duration(minutes: 5)).toIso8601String();
    final first = (json['channels'] as List).first as Map<String, dynamic>;
    final video = (first['videos'] as List).first as Map<String, dynamic>;
    final original = fixture.channels.first.videos.first;
    video['viewCount'] = (original.viewCount ?? 0) + 17;
    repository.next = Feed.fromJson(json);
    await tester.tap(find.byTooltip('Verileri yenile'));
    await tester.pumpAndSettle();
    expect(repository.refreshCalls, 2);
    final prefs = await SharedPreferences.getInstance();
    final saved = jsonDecode(prefs.getString('radar_comparison')!)
        as Map<String, dynamic>;
    expect((saved['views'] as Map)[original.id], original.viewCount);
    expect(DateTime.parse(saved['at'] as String), fixture.updatedAt);

    await disposeApp(tester);
    final restarted = _FixtureRepository(repository.next);
    await tester.pumpWidget(ShortsRadarApp(repository: restarted));
    addTearDown(restarted.dispose);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Videolar'));
    await tester.pumpAndSettle();
    await checkVideo(tester, restarted.cached.channels.first.videos.first, 1);
    final card = find
        .ancestor(of: thumbnailFor(original), matching: find.byType(InkWell))
        .first;
    expect(
        find.descendant(of: card, matching: find.text('+17')), findsOneWidget);
    await disposeApp(tester);
  });

  testWidgets(
      'failed refresh preserves cached channels and individual video views',
      (tester) async {
    final repository = _FixtureRepository(fixture)
      ..failure = const FeedException('Bağlantı yok. Son kayıt gösteriliyor.');
    await launch(tester, repository);
    expect(find.text('Bağlantı yok. Son kayıt gösteriliyor.'), findsOneWidget);
    await tester.tap(find.text('Videolar'));
    await tester.pumpAndSettle();
    await checkVideo(tester, fixture.channels.first.videos.first, 1);
    await disposeApp(tester);
  });
}
