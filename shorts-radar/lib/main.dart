import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'data.dart';

const feedUrl = 'https://www.youtube.com/feeds/videos.xml';
const ink = Color(0xFF0B0E15);
const panel = Color(0xFF171D2B);
const coral = Color(0xFFFF536D);
const muted = Color(0xFF9BA6BD);
const mint = Color(0xFF77E7BC);
const channelColors = [
  Color(0xFFFFB86B),
  Color(0xFF8EABFF),
  Color(0xFF79E0C3),
  Color(0xFFD3A0FF)
];
String number(int? n) =>
    n == null ? '—' : NumberFormat.decimalPattern('tr_TR').format(n);
String shortNumber(int? n) => n == null
    ? '—'
    : n >= 1000000
        ? '${(n / 1000000).toStringAsFixed(1).replaceAll('.', ',')} Mn'
        : n >= 1000
            ? '${(n / 1000).toStringAsFixed(1).replaceAll('.', ',')} B'
            : '$n';
String dateLabel(DateTime d) =>
    DateFormat('dd.MM.yyyy HH:mm').format(d.toLocal());

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShortsRadarApp());
}

class ShortsRadarApp extends StatelessWidget {
  const ShortsRadarApp({super.key, this.repository});
  final FeedRepository? repository;
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Shorts Radar',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: ink,
            colorScheme: ColorScheme.fromSeed(
                seedColor: coral, brightness: Brightness.dark, surface: panel),
            fontFamily: 'sans-serif',
            dividerColor: Colors.white10,
            snackBarTheme: const SnackBarThemeData(
                backgroundColor: panel,
                contentTextStyle: TextStyle(color: Colors.white)),
            appBarTheme: const AppBarTheme(
                backgroundColor: ink, foregroundColor: Colors.white),
            navigationBarTheme: const NavigationBarThemeData(
                backgroundColor: ink, indicatorColor: Color(0xFF3D2330))),
        home: Dashboard(repository: repository ?? FeedRepository()),
      );
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key, required this.repository});
  final FeedRepository repository;
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> with WidgetsBindingObserver {
  Feed? _feed;
  bool _loading = true;
  String? _error;
  int _page = 0;
  Timer? _timer;
  Map<String, int> _previousViews = {};
  DateTime? _previousAt;
  bool _auto = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = await widget.repository.loadCached();
    final raw = prefs.getString('radar_comparison');
    try {
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _previousViews = Map<String, int>.from(map['views'] as Map);
        _previousAt = DateTime.tryParse(map['at'] as String);
      }
    } catch (_) {/* A damaged comparison never blocks the feed. */}
    if (!mounted) return;
    setState(() {
      _feed = cached;
      _loading = false;
      _auto = prefs.getBool('radar_auto') ?? true;
    });
    _startTimer();
    await _refresh();
  }

  void _startTimer() {
    _timer?.cancel();
    if (_auto) {
      _timer = Timer.periodic(const Duration(minutes: 5), (_) => _refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startTimer();
      _refresh();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fresh = await widget.repository.refresh();
      final old = _feed;
      if (old != null && fresh.updatedAt.isAfter(old.updatedAt)) {
        final values = <String, int>{};
        for (final c in old.channels) {
          for (final v in c.videos) {
            if (v.viewCount != null) values[v.id] = v.viewCount!;
          }
        }
        _previousViews = values;
        _previousAt = old.updatedAt;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            'radar_comparison',
            jsonEncode(
                {'at': old.updatedAt.toIso8601String(), 'views': values}));
      }
      if (mounted) setState(() => _feed = fresh);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is FeedException
            ? e.message
            : 'Veriler alınamadı. İnternet bağlantını kontrol edip tekrar dene.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(String url) async {
    try {
      if (!await launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication)) {
        throw Exception();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Bağlantı açılamadı.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          titleSpacing: 20,
          title: Row(children: [
            Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color: coral, borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 24)),
            const SizedBox(width: 10),
            const Expanded(
                child: Text('Shorts Radar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 21)))
          ]),
          actions: [
            IconButton(
                onPressed: _loading ? null : _refresh,
                tooltip: 'Verileri yenile',
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: coral))
                    : const Icon(Icons.refresh_rounded)),
            const SizedBox(width: 8)
          ]),
      body: SafeArea(
          child: _feed == null
              ? _empty()
              : RefreshIndicator(
                  color: coral,
                  onRefresh: _refresh,
                  child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        if (_error != null)
                          _notice(_error!, Icons.cloud_off_rounded, coral),
                        if (_page == 0) ..._overview(_feed!),
                        if (_page == 1) ..._allVideos(_feed!),
                        if (_page == 2) ..._settings(_feed!),
                      ]))),
      bottomNavigationBar: NavigationBar(
          selectedIndex: _page,
          onDestinationSelected: (i) => setState(() => _page = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.space_dashboard_outlined),
                selectedIcon: Icon(Icons.space_dashboard_rounded),
                label: 'Genel bakış'),
            NavigationDestination(
                icon: Icon(Icons.video_library_outlined),
                selectedIcon: Icon(Icons.video_library_rounded),
                label: 'Videolar'),
            NavigationDestination(
                icon: Icon(Icons.tune_rounded), label: 'Ayarlar')
          ]),
    );
  }

  Widget _empty() => Center(
      child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_loading)
              const CircularProgressIndicator(color: coral)
            else
              const Icon(Icons.cloud_off_rounded, size: 48, color: muted),
            const SizedBox(height: 18),
            Text(_error ?? 'Kanalların hazırlanıyor…',
                textAlign: TextAlign.center),
            const SizedBox(height: 18),
            if (!_loading)
              FilledButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Tekrar dene'))
          ])));
  List<Widget> _overview(Feed feed) {
    final videos = feed.channels.expand((c) => c.videos).toList();
    final known = videos.where((v) => v.viewCount != null).toList();
    final total = known.fold<int>(0, (a, b) => a + b.viewCount!);
    final recent = [...videos]
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return [
      const SizedBox(height: 10),
      const Text('KANALLARIN, TEK EKRANDA',
          style: TextStyle(
              color: muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.9)),
      const SizedBox(height: 10),
      const Text('Büyümeyi takip et.',
          style: TextStyle(
              fontSize: 29,
              height: 1.1,
              fontWeight: FontWeight.w800,
              letterSpacing: -.8)),
      const SizedBox(height: 10),
      _freshness(feed),
      const SizedBox(height: 24),
      Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF3D253D), Color(0xFF20253E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF594057))),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.bar_chart_rounded, color: coral, size: 20),
              SizedBox(width: 8),
              Expanded(
                  child: Text('SON VİDEOLARIN İZLENMESİ',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: Color(0xFFE5B9C9))))
            ]),
            const SizedBox(height: 14),
            Text(known.isEmpty ? '—' : number(total),
                style: const TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.5)),
            const SizedBox(height: 6),
            Text(
                '${feed.channels.length} kanal · ${videos.length} video${known.length != videos.length ? ' · ${known.length} videonun sayacı mevcut' : ''}',
                style: const TextStyle(color: muted, fontSize: 13))
          ])),
      const SizedBox(height: 26),
      _section('Kanallarım', '${feed.channels.length} kanal'),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, box) {
        final width = box.maxWidth;
        final columns =
            width < 340 || MediaQuery.textScalerOf(context).scale(1) > 1.3
                ? 1
                : width > 700
                    ? 4
                    : 2;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (int i = 0; i < feed.channels.length; i++)
            SizedBox(
                width: (width - (columns - 1) * 12) / columns,
                child: _channelCard(feed.channels[i], i))
        ]);
      }),
      const SizedBox(height: 26),
      _section('En yeni videolar', 'Tüm kanallar'),
      const SizedBox(height: 12),
      for (final video in recent.take(4))
        _videoCard(
            video,
            feed.channels
                .firstWhere((c) => c.videos.any((v) => v.id == video.id))),
      if (recent.isEmpty)
        _notice('Henüz yayınlanmış video bilgisi yok.', Icons.movie_outlined,
            muted),
    ];
  }

  Widget _freshness(Feed feed) {
    final stale = DateTime.now().difference(feed.updatedAt).inHours >= 2;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.only(top: 4),
          child:
              Icon(Icons.circle, size: 7, color: stale ? Colors.amber : mint)),
      const SizedBox(width: 7),
      Expanded(
          child: Text(
              '${stale ? 'Son kayıt' : 'Son kontrol'}: ${dateLabel(feed.updatedAt)}',
              style: const TextStyle(color: muted, fontSize: 12)))
    ]);
  }

  Widget _channelCard(ChannelStats channel, int index) {
    final color = channelColors[index % channelColors.length];
    final views = channel.videos.where((v) => v.viewCount != null).toList();
    return Material(
        color: panel,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _showChannel(channel, color),
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                                color: color.withValues(alpha: .13),
                                borderRadius: BorderRadius.circular(12)),
                            child: Icon(
                                [
                                  Icons.public_rounded,
                                  Icons.language_rounded,
                                  Icons.psychology_rounded,
                                  Icons.auto_awesome_rounded
                                ][index % 4],
                                color: color,
                                size: 21)),
                        const Spacer(),
                        const Icon(Icons.arrow_outward_rounded,
                            size: 17, color: muted)
                      ]),
                      const SizedBox(height: 17),
                      Text(channel.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 5),
                      Text(channel.handle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: muted)),
                      const SizedBox(height: 18),
                      Text(
                          views.isEmpty
                              ? '—'
                              : number(views.fold<int>(
                                  0, (sum, v) => sum + v.viewCount!)),
                          style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.5)),
                      const SizedBox(height: 4),
                      Text('Son ${channel.videos.length} video · izlenme',
                          style: const TextStyle(fontSize: 11, color: muted)),
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Row(children: [
                        Icon(
                            channel.error == null
                                ? Icons.people_outline
                                : Icons.info_outline,
                            size: 15,
                            color:
                                channel.error == null ? muted : Colors.amber),
                        const SizedBox(width: 5),
                        Expanded(
                            child: Text(
                                channel.error == null
                                    ? '${number(channel.subscriberCount)} abone'
                                    : 'Güncelleme bekliyor',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: channel.error == null
                                        ? muted
                                        : Colors.amber)))
                      ]),
                    ]))));
  }

  Widget _section(String title, String trailing) => Row(children: [
        Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontSize: 19, fontWeight: FontWeight.w700))),
        Text(trailing, style: const TextStyle(color: muted, fontSize: 11))
      ]);
  Widget _notice(String message, IconData icon, Color color) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .25))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message,
                style: const TextStyle(fontSize: 12, height: 1.4)))
      ]));
  Widget _videoCard(VideoStats v, ChannelStats channel, {int? rank}) {
    final previous = _previousViews[v.id];
    final delta = previous != null && v.viewCount != null
        ? v.viewCount! - previous
        : null;
    return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
            color: panel, borderRadius: BorderRadius.circular(17)),
        child: InkWell(
            borderRadius: BorderRadius.circular(17),
            onTap: () => _open(v.url),
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                              width: 68,
                              height: 94,
                              child: Stack(fit: StackFit.expand, children: [
                                Image.network(v.thumbnail,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, error, stack) =>
                                        Container(
                                            color: const Color(0xFF252D40),
                                            child: const Icon(
                                                Icons.play_circle_outline,
                                                color: muted))),
                                Positioned(
                                    left: 4,
                                    top: 4,
                                    child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: Colors.black
                                                .withValues(alpha: .7),
                                            borderRadius:
                                                BorderRadius.circular(4)),
                                        child: Text(
                                            rank != null ? '#$rank' : 'SHORTS',
                                            style: const TextStyle(
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold))))
                              ]))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(v.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    height: 1.35)),
                            const SizedBox(height: 5),
                            Text(
                                '${channel.title} · ${DateFormat('dd.MM.yyyy').format(v.publishedAt.toLocal())}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: muted, fontSize: 10)),
                            const SizedBox(height: 10),
                            Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(number(v.viewCount),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 19)),
                                  const Text('izlenme',
                                      style: TextStyle(
                                          color: muted, fontSize: 10)),
                                  if (delta != null && delta != 0)
                                    Text(
                                        '${delta > 0 ? '+' : ''}${number(delta)}',
                                        style: TextStyle(
                                            color: delta >= 0
                                                ? mint
                                                : Colors.amber,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold))
                                ])
                          ])),
                    ]))));
  }

  List<Widget> _allVideos(Feed feed) => [
        const SizedBox(height: 12),
        const Text('Video kütüphanesi',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Her kanalın son 10 videosu, en yeniden eskiye.',
            style: TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 18),
        for (final channel in feed.channels) ...[
          _section(channel.title, '${channel.videos.length} video'),
          const SizedBox(height: 12),
          if (channel.error != null)
            _notice(channel.error!, Icons.info_outline, Colors.amber),
          for (int i = 0; i < channel.videos.length; i++)
            _videoCard(channel.videos[i], channel, rank: i + 1),
          const SizedBox(height: 18)
        ]
      ];
  void _showChannel(ChannelStats channel, Color color) {
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: ink,
        builder: (context) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: .88,
            minChildSize: .5,
            maxChildSize: .95,
            builder: (context, controller) => ListView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                    children: [
                      Text(channel.title,
                          style: const TextStyle(
                              fontSize: 27, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(channel.handle, style: TextStyle(color: color)),
                      const SizedBox(height: 18),
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        _metric('Abone', channel.subscriberCount),
                        _metric('Kanal izlenmesi', channel.viewCount),
                        _metric('Toplam video', channel.videoCount)
                      ]),
                      const SizedBox(height: 14),
                      Text('Kanal veri zamanı: ${dateLabel(channel.updatedAt)}',
                          style: const TextStyle(color: muted, fontSize: 11)),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                          onPressed: () => _open(channel.url),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('YouTube’da kanalı aç')),
                      const SizedBox(height: 22),
                      if (channel.error != null)
                        _notice(
                            channel.error!, Icons.info_outline, Colors.amber),
                      _section('Son 10 video', 'Tek tek izlenmeler'),
                      const SizedBox(height: 6),
                      if (_previousAt != null)
                        Text(
                            'Değişim, ${dateLabel(_previousAt!)} kaydına göre.',
                            style: const TextStyle(color: muted, fontSize: 10)),
                      const SizedBox(height: 12),
                      if (channel.videos.isEmpty)
                        _notice('Video listesi henüz alınamadı.',
                            Icons.movie_outlined, muted),
                      for (int i = 0; i < channel.videos.length; i++)
                        _videoCard(channel.videos[i], channel, rank: i + 1)
                    ])));
  }

  Widget _metric(String label, int? value) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration:
          BoxDecoration(color: panel, borderRadius: BorderRadius.circular(13)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(number(value),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: muted, fontSize: 10))
      ]));
  List<Widget> _settings(Feed feed) => [
        const SizedBox(height: 12),
        const Text('Takip ayarları',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 22),
        Container(
            decoration: BoxDecoration(
                color: panel, borderRadius: BorderRadius.circular(18)),
            child: SwitchListTile.adaptive(
                value: _auto,
                activeTrackColor: coral,
                onChanged: (value) async {
                  setState(() => _auto = value);
                  _startTimer();
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('radar_auto', value);
                },
                title: const Text('Otomatik yenile',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                subtitle: const Text(
                    'Uygulama açıkken 5 dakikada bir kontrol eder.',
                    style: TextStyle(fontSize: 12, color: muted)))),
        const SizedBox(height: 18),
        _notice(
            'İzlenmeler doğrudan YouTube’un herkese açık video akışından alınır. YouTube önbelleği nedeniyle sayaçlar gecikebilir. İnternet yokken son kayıt gösterilir.',
            Icons.info_outline,
            muted),
        _notice(
            'Yeşil + sayılar, cihazında kayıtlı önceki veriyle farkı gösterir. İlk açılışta karşılaştırma bulunmayabilir. YouTube sayaç düzeltmeleri nedeniyle azalma olabilir.',
            Icons.trending_up_rounded,
            mint),
        _freshness(feed),
        const SizedBox(height: 24),
        const Text('BAĞLI REPOLAR',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: muted,
                letterSpacing: 1.5)),
        const SizedBox(height: 10),
        for (final channel in feed.channels)
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(channel.title, style: const TextStyle(fontSize: 14)),
              subtitle: Text(channel.repository,
                  style: const TextStyle(fontSize: 11, color: muted)),
              trailing: const Icon(Icons.open_in_new, size: 17),
              onTap: () => _open('https://github.com/${channel.repository}')),
        const Divider(),
        TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: feedUrl));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Veri kaynağı bağlantısı kopyalandı.')));
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Veri kaynağı bağlantısını kopyala')),
        const SizedBox(height: 10),
        const Center(
            child: Text('Shorts Radar · 1.0.0\nDört kanal. Tek bakış.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 12, height: 1.7)))
      ];
}
