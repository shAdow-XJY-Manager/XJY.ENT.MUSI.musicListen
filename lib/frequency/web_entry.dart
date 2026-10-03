import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_common/flutter_common.dart';
import 'browser_io.dart';

void start() => runApp(const MusicApp());

class Track {
  final String id, title, artist, url, source;
  const Track(this.id, this.title, this.artist, this.url, this.source);
}

const bundledTracks = [
  Track('0', 'Beyond the Happy End', 'Kohei Tanaka', 'assets/assets/music/KoheiTanaka_BeyondtheHappyEnd.mp3', '内置本地音频'),
  Track('1', 'Fleeting Fragment of Memory', 'Kohei Tanaka', 'assets/assets/music/KoheiTanaka_FleetingFragmentofMemory.mp3', '内置本地音频'),
  Track('2', 'If You Are With You', 'Kohei Tanaka', 'assets/assets/music/KoheiTanaka_Ifyouarewithyou.mp3', '内置本地音频'),
  Track('3', 'Small Guide', 'Kohei Tanaka', 'assets/assets/music/KoheiTanaka_Smallguide.mp3', '内置本地音频'),
];

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(title: '声音播放 · 频率站', debugShowCheckedModeBanner: false, theme: FrequencyTheme.dark(), home: const MusicDesk());
}

class MusicDesk extends StatefulWidget {
  const MusicDesk({super.key});
  @override
  State<MusicDesk> createState() => _MusicDeskState();
}

class _MusicDeskState extends State<MusicDesk> {
  bool exiting = false;
  final audio = html.AudioElement()..preload = 'metadata';
  final searchFocus = FocusNode();
  final tracks = <Track>[...bundledTracks];
  final subscriptions = <StreamSubscription<html.Event>>[];
  final blobs = <String>[];
  int selected = -1, repeat = 0, request = 0;
  bool playing = false, loading = false, mediaFailed = false;
  double position = 0, duration = 0, volume = .75;
  double? restorePosition;
  String error = '', query = '';
  Timer? saveTimer;
  @override
  void initState() {
    super.initState();
    void listen(Stream<html.Event> stream, void Function() action) => subscriptions.add(stream.listen((_) { if (mounted) action(); }));
    listen(audio.onPlaying, () => setState(() { playing = true; loading = false; mediaFailed = false; error = ''; }));
    listen(audio.onPause, () => setState(() => playing = false));
    listen(audio.onWaiting, () => setState(() => loading = true));
    listen(audio.onCanPlay, () => setState(() => loading = false));
    listen(audio.onLoadedMetadata, () {
      setState(() { duration = audio.duration.isFinite ? audio.duration.toDouble() : 0; loading = false; });
      if (restorePosition != null && duration > 0) { audio.currentTime = restorePosition!.clamp(0, duration); restorePosition = null; }
    });
    listen(audio.onTimeUpdate, () {
      setState(() => position = audio.currentTime.isFinite ? audio.currentTime.toDouble() : 0);
      saveTimer ??= Timer(const Duration(seconds: 2), () { saveTimer = null; save(); });
    });
    listen(audio.onError, () => setState(() { error = '音频无法加载或解码。检查来源地址，或重新选择文件。'; loading = false; playing = false; mediaFailed = true; }));
    listen(audio.onEnded, () {
      setState(() => playing = false);
      if (repeat == 2) { audio.currentTime = 0; play(); }
      else if (selected + 1 < tracks.length) { choose(selected + 1); }
      else if (repeat == 1) { choose(0); }
      else { save(); }
    });
    try {
      final raw = readLocal('frequency.music.progress.v1');
      if (raw != null) { final j = jsonDecode(raw); volume = (j['volume'] as num? ?? .75).toDouble().clamp(0, 1); final index = tracks.indexWhere((t) => t.id == j['id']); if (index >= 0) { selected = index; restorePosition = (j['position'] as num? ?? 0).toDouble(); audio.src = Uri.base.resolve(tracks[index].url).toString(); } }
    } catch (_) { error = '本地播放记录未能读取。可以重新选择曲目。'; }
    audio.volume = volume;
  }
  void save() {
    if (selected < 0 || !bundledTracks.any((t) => t.id == tracks[selected].id)) return;
    try { writeLocal('frequency.music.progress.v1', jsonEncode({'id': tracks[selected].id, 'position': position, 'volume': volume})); }
    catch (_) { if (mounted && !exiting && error.isEmpty) setState(() => error = '本浏览器未能保存播放记录。音频仍可继续播放。'); }
  }
  Future<void> choose(int index) async {
    if (index < 0 || index >= tracks.length) return;
    save();
    request++;
    audio.pause();
    restorePosition = null;
    setState(() { selected = index; position = 0; duration = 0; error = ''; loading = true; mediaFailed = false; });
    audio.src = tracks[index].url.startsWith('blob:') || tracks[index].url.startsWith('https:') ? tracks[index].url : Uri.base.resolve(tracks[index].url).toString();
    audio.load();
    await play();
  }
  Future<void> play() async {
    final token = request;
    try { await audio.play(); }
    catch (e) { if (mounted && token == request) setState(() { loading = false; if (!mediaFailed) error = '暂时无法播放，请点击重试。浏览器可能需要一次主动点击。'; }); }
  }
  KeyEventResult handleShortcut(FocusNode node, KeyEvent event) {
    if (searchFocus.hasFocus || event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.space) {
      unawaited(toggle());
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isAltPressed && event.logicalKey == LogicalKeyboardKey.arrowRight) {
      unawaited(choose(selected + 1));
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isAltPressed && event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      unawaited(choose(selected - 1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
  Future<void> toggle() async {
    if (selected < 0) { await choose(0); return; }
    if (mediaFailed) { await choose(selected); return; }
    if (playing) { audio.pause(); save(); }
    else { await play(); }
  }
  Future<void> addFile() async {
    try {
      final file = await pickFile('audio/*,.mp3,.wav,.ogg,.m4a', maxBytes: 50 * 1024 * 1024);
      if (file == null || !mounted) return;
      final url = html.Url.createObjectUrlFromBlob(html.Blob([Uint8List.fromList(file.bytes)]));
      blobs.add(url);
      setState(() => tracks.add(Track('file-${DateTime.now().microsecondsSinceEpoch}', file.name, '你的音频', url, '用户文件 · 仅本次会话')));
      await choose(tracks.length - 1);
    } catch (e) { if (mounted) setState(() => error = '文件打开失败：$e'); }
  }
  Future<void> addUrl() async {
    final value = await showDialog<String>(context: context, builder: (_) => const _AudioSourceDialog());
    if (value == null || !mounted) return;
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) { setState(() => error = '请输入完整 HTTPS 音频直链。'); return; }
    setState(() => tracks.add(Track('url-${DateTime.now().microsecondsSinceEpoch}', uri.pathSegments.isEmpty ? uri.host : uri.pathSegments.last, uri.host, value, '网络音频 · ${uri.host}')));
    await choose(tracks.length - 1);
  }
  String time(double seconds) => '${seconds ~/ 60}:${(seconds.toInt() % 60).toString().padLeft(2, '0')}';
  @override
  void dispose() { exiting = true;
    saveTimer?.cancel(); save();
    for (final sub in subscriptions) { sub.cancel(); }
    audio.pause(); audio.src = ''; audio.remove(); searchFocus.dispose();
    for (final url in blobs) { html.Url.revokeObjectUrl(url); }
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final track = selected >= 0 ? tracks[selected] : null;
    final visible = tracks.asMap().entries.where((e) => '${e.value.title} ${e.value.artist}'.toLowerCase().contains(query.toLowerCase())).toList();
    final wide = MediaQuery.sizeOf(context).width >= 700;
    return Focus(onKeyEvent: handleShortcut, child: Focus(autofocus: true, child: Scaffold(appBar: AppBar(title: const Text('声音播放'), actions: [IconButton(tooltip: '打开本地音频', onPressed: addFile, icon: const Icon(Icons.audio_file_outlined)), IconButton(tooltip: '添加网络音频', onPressed: addUrl, icon: const Icon(Icons.link)), const SizedBox(width: 12)]),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: ListView(padding: const EdgeInsets.all(24), children: [const Text('LISTEN / 03', style: TextStyle(color: FrequencyPalette.accent, fontSize: 12)), const SizedBox(height: 12), const Text('给今天，\n留一段声音。', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, height: 1.2)), const SizedBox(height: 16), const Text('选择曲目，或打开自己的音频。空格播放 / 暂停，Alt + 左右切歌。', style: TextStyle(color: FrequencyPalette.muted)), const SizedBox(height: 32),
      TextField(focusNode: searchFocus, decoration: const InputDecoration(labelText: '查找曲名或音乐人', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => query = v)), const SizedBox(height: 24),
      if (visible.isEmpty) const Padding(padding: EdgeInsets.all(32), child: Text('没有匹配曲目。换一个词或添加自己的音频。')),
      for (final entry in visible) Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(child: ListTile(selected: selected == entry.key, contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), leading: Icon(selected == entry.key && playing ? Icons.graphic_eq : Icons.music_note_outlined, color: selected == entry.key ? FrequencyPalette.accent : FrequencyPalette.muted), title: Text(entry.value.title), subtitle: Text('${entry.value.artist}\n${entry.value.source}'), isThreeLine: true, trailing: IconButton(tooltip: '播放 ${entry.value.title}', onPressed: () => choose(entry.key), icon: const Icon(Icons.play_arrow_rounded)), onTap: () => choose(entry.key)))),
      const SizedBox(height: 16), const Text('用户文件和新增直链仅在本次会话中保留；刷新后恢复内置曲目的记录，不自动播放。', style: TextStyle(color: FrequencyPalette.muted)),
    ]))),
    bottomNavigationBar: SafeArea(top: false, child: Material(color: FrequencyPalette.surface, child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [const Icon(Icons.headphones_rounded, color: FrequencyPalette.accent), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(track?.title ?? '还没有开始播放', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)), Text(error.isNotEmpty ? error : loading ? '正在加载音频…' : playing ? '正在播放 · ${track?.source ?? ''}' : selected < 0 ? '选择一首曲目开始' : '已暂停 · 点击播放继续', style: TextStyle(color: error.isNotEmpty ? FrequencyPalette.error : FrequencyPalette.muted))])), if (loading) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))]),
      Row(children: [Text(time(position)), Expanded(child: Slider(min: 0, max: duration > 0 ? duration : 1, value: position.clamp(0, duration > 0 ? duration : 1), onChanged: duration > 0 ? (v) { audio.currentTime = v; setState(() => position = v); save(); } : null, semanticFormatterCallback: (v) => time(v))), Text(time(duration))]),
      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 12, runSpacing: 8, children: [IconButton(tooltip: '上一首', onPressed: selected > 0 ? () => choose(selected - 1) : null, icon: const Icon(Icons.skip_previous)), FilledButton.icon(onPressed: toggle, icon: Icon(playing ? Icons.pause : Icons.play_arrow), label: Text(mediaFailed ? '重试播放' : playing ? '暂停' : '播放')), IconButton(tooltip: '下一首', onPressed: selected + 1 < tracks.length ? () => choose(selected + 1) : null, icon: const Icon(Icons.skip_next)), PopupMenuButton<int>(tooltip: '播放顺序', initialValue: repeat, onSelected: (v) => setState(() => repeat = v), itemBuilder: (_) => const [PopupMenuItem(value: 0, child: Text('顺序播放')), PopupMenuItem(value: 1, child: Text('循环列表')), PopupMenuItem(value: 2, child: Text('单曲循环'))], child: Padding(padding: const EdgeInsets.all(12), child: Text(['顺序播放', '循环列表', '单曲循环'][repeat]))), SizedBox(width: wide ? 200 : 150, child: Row(children: [IconButton(tooltip: volume == 0 ? '恢复音量' : '静音', onPressed: () { setState(() => volume = volume == 0 ? .75 : 0); audio.volume = volume; save(); }, icon: Icon(volume == 0 ? Icons.volume_off : Icons.volume_up)), Expanded(child: Slider(value: volume, onChanged: (v) { setState(() => volume = v); audio.volume = v; save(); }, semanticFormatterCallback: (v) => '音量 ${(v * 100).round()}%'))]))]),
    ])))))));
  }
}

class _AudioSourceDialog extends StatefulWidget {
  const _AudioSourceDialog();
  @override
  State<_AudioSourceDialog> createState() => _AudioSourceDialogState();
}

class _AudioSourceDialogState extends State<_AudioSourceDialog> {
  final controller = TextEditingController();
  @override
  void dispose() { controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('添加音频来源'),
    content: SizedBox(width: 420, child: TextField(
      controller: controller, autofocus: true,
      decoration: const InputDecoration(labelText: 'HTTPS 音频直链', hintText: 'https://…/audio.mp3'),
      keyboardType: TextInputType.url,
      onSubmitted: (value) => Navigator.pop(context, value.trim()),
    )),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('添加并播放')),
    ],
  );
}
