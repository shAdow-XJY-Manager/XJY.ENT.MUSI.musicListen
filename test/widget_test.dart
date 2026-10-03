@TestOn('browser')
library;

import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_listen/frequency/web_entry.dart';

const progressKey = 'frequency.music.progress.v1';

// Inspect the actual browser player; a paused label alone cannot prove silence.
html.AudioElement player(WidgetTester tester) =>
    (tester.state(find.byType(MusicDesk)) as dynamic).audio
        as html.AudioElement;

Future<void> mount(WidgetTester tester,
    {double width = 1280, double height = 1200}) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    html.window.localStorage.remove(progressKey);
    await tester.binding.setSurfaceSize(null);
  });
  await tester.binding.setSurfaceSize(Size(width, height));
  await tester.pumpWidget(const MusicApp());
  await tester.pumpAndSettle();
}

void main() {

  setUp(() => html.window.localStorage.remove(progressKey));

  for (final width in [390.0, 768.0, 1280.0]) {
    testWidgets('声音播放入口在 ${width.toInt()}px 保持播放器静止', (tester) async {
      await mount(tester, width: width, height: 900);
      expect(find.text('声音播放'), findsOneWidget);
      expect(find.text('还没有开始播放'), findsOneWidget);
      expect(find.text('选择一首曲目开始'), findsOneWidget);
      expect(player(tester).paused, isTrue);
      expect(player(tester).autoplay, isFalse);
      expect(player(tester).played.length, 0);
      expect(player(tester).getAttribute('src'), isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('恢复内置曲目与音量仍不自动播放', (tester) async {
    html.window.localStorage[progressKey] = jsonEncode({
      'id': bundledTracks[2].id,
      'position': 35,
      'volume': .4,
    });
    await mount(tester);
    final audio = player(tester);
    expect(audio.paused, isTrue);
    expect(audio.autoplay, isFalse);
    expect(audio.played.length, 0);
    expect(audio.volume, closeTo(.4, .001));
    expect(audio.src, Uri.base.resolve(bundledTracks[2].url).toString());
    expect(
        tester
            .widget<ListTile>(
                find.widgetWithText(ListTile, bundledTracks[2].title))
            .selected,
        isTrue);
    expect(find.text('暂停'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('会话文件失效后不请求旧 blob 来源', (tester) async {
    html.window.localStorage[progressKey] = jsonEncode({
      'id': 'file-expired-session',
      'position': 10,
      'volume': 5,
    });
    await mount(tester);
    expect(find.text('还没有开始播放'), findsOneWidget);
    expect(player(tester).getAttribute('src'), isNull);
    expect(player(tester).volume, 1);
    expect(player(tester).paused, isTrue);
    expect(tester.widget<IconButton>(find.byWidgetPredicate((w) => w is IconButton && w.tooltip == '上一首')).onPressed, isNull);
  });

  testWidgets('损坏播放记录不启动音频且显示恢复路径', (tester) async {
    html.window.localStorage[progressKey] = '{broken';
    await mount(tester);
    expect(find.text('本地播放记录未能读取。可以重新选择曲目。'), findsOneWidget);
    expect(player(tester).paused, isTrue);
    expect(player(tester).getAttribute('src'), isNull);
    expect(html.window.localStorage[progressKey], '{broken');
  });

  testWidgets('查找曲名和音乐人不启动播放', (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'small guide');
    await tester.pump();
    expect(find.widgetWithText(ListTile, 'Small Guide'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Beyond the Happy End'), findsNothing);
    await tester.enterText(find.byType(TextField), 'kohei tanaka');
    await tester.pump();
    expect(find.byType(ListTile), findsNWidgets(bundledTracks.length));
    expect(player(tester).paused, isTrue);
    expect(player(tester).getAttribute('src'), isNull);
  });

  testWidgets('拒绝非 HTTPS 来源且原曲目列表不变', (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('添加网络音频'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    await tester.enterText(
        find.descendant(of: dialog, matching: find.byType(TextField)),
        'http://example.invalid/audio.mp3');
    await tester.tap(find.text('添加并播放'));
    await tester.pumpAndSettle();
    expect(find.text('请输入完整 HTTPS 音频直链。'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(bundledTracks.length));
    expect(player(tester).getAttribute('src'), isNull);
    expect(player(tester).paused, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('恢复后静音切换写入真实浏览器音量与记录', (tester) async {
    html.window.localStorage[progressKey] = jsonEncode({
      'id': bundledTracks[0].id,
      'position': 0,
      'volume': .4,
    });
    await mount(tester);
    await tester.tap(find.byTooltip('静音'));
    await tester.pump();
    expect(player(tester).volume, 0);
    expect(jsonDecode(html.window.localStorage[progressKey]!)['volume'], 0);
    expect(player(tester).paused, isTrue);
    await tester.tap(find.byTooltip('恢复音量'));
    await tester.pump();
    expect(player(tester).volume, closeTo(.75, .001));
    expect(jsonDecode(html.window.localStorage[progressKey]!)['volume'], .75);
    expect(player(tester).paused, isTrue);
  });
}
