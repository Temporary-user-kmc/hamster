import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

void main() => runApp(
  const MaterialApp(debugShowCheckedModeBanner: false, home: UnicornSlot()),
);

const rainbow = [
  Color(0xFFFF1744),
  Color(0xFFFF9100),
  Color(0xFFFFEA00),
  Color(0xFF00E676),
  Color(0xFF00E5FF),
  Color(0xFF2979FF),
  Color(0xFFD500F9),
];

const wiki = 'https://static.wikia.nocookie.net/gundam/images';

// 数字 1〜8 それぞれの図柄に使うバナージ（images[n - 1] が数字 n）
const images = [
  '$wiki/5/55/Banagher_Links_Newtype.jpg/revision/latest/scale-to-width-down/600',
  '$wiki/d/df/Banagher_Links_Pilot_Suit_Face.jpg/revision/latest/scale-to-width-down/600',
  '$wiki/1/17/Banagher_Links_Screenshot.jpg/revision/latest/scale-to-width-down/600',
  '$wiki/7/77/Banagher_Links_%28NT_Narrative%29.jpg/revision/latest/scale-to-width-down/600',
  '$wiki/8/89/Banagher_Links_%28UC_Perfectibility%29.jpg/revision/latest',
  '$wiki/9/94/Banagher_Smiling_01_%28Unicorn_0096_Ep14%29.png/revision/latest/scale-to-width-down/600',
  '$wiki/f/f3/XB_Burst_Banagher.jpg/revision/latest/scale-to-width-down/600',
  '$wiki/3/3f/Banagher_Pilot_Suit_01_%28Unicorn_0096_Ep5%29.png/revision/latest/scale-to-width-down/600',
];

// 777 になったときだけ出るレア画像
const rareImages = [
  '$wiki/7/7e/Banagher_links_01.jpg/revision/latest/scale-to-width-down/600',
  '$wiki/d/d1/Banagher-daguza-illust.jpg/revision/latest/scale-to-width-down/600',
  '$wiki/c/c7/Links.jpg/revision/latest/scale-to-width-down/600',
];

// 回転中の数字タイルの色
const tileColors = [
  Color(0xFFE53935), // 1
  Color(0xFF1E88E5), // 2
  Color(0xFFFF7043), // 3
  Color(0xFF43A047), // 4
  Color(0xFF8E24AA), // 5
  Color(0xFF00897B), // 6
  Color(0xFFFFA000), // 7
  Color(0xFFD81B60), // 8
];

// 全画面演出の段階
enum Fx { none, win, soredemo, flash, premium }

// レバーを引いた瞬間に決まる結果
enum Outcome { hit, reachMiss, miss }

class UnicornSlot extends StatefulWidget {
  const UnicornSlot({super.key});

  @override
  State<UnicornSlot> createState() => _UnicornSlotState();
}

class _UnicornSlotState extends State<UnicornSlot>
    with TickerProviderStateMixin {
  static const tileW = 104.0, tileH = 150.0;
  static const ceiling = 20; // 天井：この回転数で必ず当たる

  final rand = Random();
  final pos = [0.0, 2.0, 5.0]; // 各列の回転位置（整数のとき数字ぴったり）
  final spinning = [false, false, false];
  final List<double?> target = [null, null, null];
  final List<int?> result = [null, null, null]; // ボタンで決まった数字
  final landKey = [0, 0, 0]; // 止まった瞬間のバウンド用
  Outcome outcome = Outcome.miss;
  int hitNum = 1, winNum = 1;
  int spins = 0, bonusCount = 0, sinceHit = 0;
  bool reach = false;
  int reachLevel = 0; // 0:青 1:赤 2:金(激アツ) 3:虹(超激アツ)
  bool chance = false; // 予告
  bool bonus = false; // 777 になった
  bool busy = false; // 演出中はレバーを引けない
  bool leverDown = false;
  String? banner;
  Fx fx = Fx.none;
  DateTime fxStart = DateTime.now();
  late final Timer timer;
  late final AnimationController fxTicker = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );
  late final AnimationController pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..repeat(reverse: true);
  final spinPlayer = AudioPlayer(); // 回転中にループする音
  bool muted = false;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(milliseconds: 16), tick);
    spinPlayer.setReleaseMode(ReleaseMode.loop);
  }

  // 効果音を1回鳴らす（鳴り終わったらプレイヤーを片付ける）
  void play(String name, {double volume = 1}) {
    if (muted) return;
    final p = AudioPlayer();
    p.onPlayerComplete.first.then((_) => p.dispose());
    p.play(AssetSource('sounds/$name.wav'), volume: volume);
  }

  @override
  void dispose() {
    timer.cancel();
    fxTicker.dispose();
    pulse.dispose();
    spinPlayer.dispose();
    super.dispose();
  }

  bool get anySpinning => spinning.contains(true);

  // 位置 p で表示される数字（1〜8）
  int numAt(num p) => p.floor() % 8 + 1;

  void tick(Timer _) {
    if (!anySpinning) return;
    setState(() {
      for (int i = 0; i < 3; i++) {
        if (!spinning[i]) continue;
        final reachCol = reach && i == reachColumn;
        final speed = reachCol ? 0.10 : 0.28;
        final t = target[i];
        if (t == null) {
          pos[i] += speed;
          continue;
        }
        // 止める位置に向かってだんだん遅くする。リーチの列はじっくり。
        final remain = t - pos[i];
        final step = max(
          reachCol ? 0.015 : 0.03,
          min(speed, remain * (reachCol ? 0.04 : 0.15)),
        );
        if (remain <= step) {
          pos[i] = t;
          spinning[i] = false;
          landKey[i]++;
          play('stop');
          if (!anySpinning) finish();
        } else {
          pos[i] += step;
        }
      }
    });
  }

  int get reachColumn => result.indexWhere((r) => r == null);

  void pull() {
    if (anySpinning || busy) return;
    setState(() {
      leverDown = true;
      spins++;
      final forced = sinceHit + 1 >= ceiling;
      if (forced || rand.nextInt(10) == 0) {
        outcome = Outcome.hit; // 1/10 でそろう
      } else if (rand.nextInt(4) == 0) {
        outcome = Outcome.reachMiss; // ハズレでも 1/4 でリーチ
      } else {
        outcome = Outcome.miss;
      }
      hitNum = rand.nextInt(8) + 1;
      final chanceRate = switch (outcome) {
        Outcome.hit => 0.5,
        Outcome.reachMiss => 0.2,
        Outcome.miss => 0.06,
      };
      chance = rand.nextDouble() < chanceRate;
      reach = false;
      bonus = false;
      banner = null;
      for (int i = 0; i < 3; i++) {
        pos[i] %= 8;
        spinning[i] = true;
        target[i] = null;
        result[i] = null;
      }
    });
    play('lever');
    if (!muted) {
      spinPlayer.setPlaybackRate(1);
      spinPlayer.play(AssetSource('sounds/spin.wav'), volume: 0.35);
    }
    if (chance) {
      Future.delayed(const Duration(milliseconds: 250), () => play('chance'));
    }
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => leverDown = false);
    });
  }

  // ボタンを押した列に出す数字を決める
  int decide() {
    final decided = result.whereType<int>().toList();
    switch (outcome) {
      case Outcome.hit:
        return hitNum;
      case Outcome.reachMiss:
        if (decided.length < 2) return hitNum;
        // 前後ハズレ：1つずれた数字で止まる
        return (hitNum - 1 + (rand.nextBool() ? 1 : 7)) % 8 + 1;
      case Outcome.miss:
        int n = rand.nextInt(8) + 1;
        while (decided.length == 1 && n == decided[0]) {
          n = rand.nextInt(8) + 1;
        }
        return n;
    }
  }

  void stop(int i) {
    if (!spinning[i] || result[i] != null) return;
    final isReachCol = reach;
    final n = decide();
    // 少なくとも2コマ先、リーチなら1周多く回してから目的の数字で止める
    int t = (pos[i] + 2 + (isReachCol ? 8 : 0)).ceil();
    while (numAt(t) != n) {
      t++;
    }
    setState(() {
      result[i] = n;
      target[i] = t.toDouble();
      final decided = result.whereType<int>().toList();
      if (decided.length == 2 && decided[0] == decided[1]) startReach();
    });
  }

  void startReach() {
    reach = true;
    chance = false;
    // 当たりのときほど熱い色が出やすい
    final weights = outcome == Outcome.hit
        ? (hitNum == 7 ? [0, 0, 50, 50] : [10, 35, 35, 20])
        : [60, 32, 8, 0];
    int r = rand.nextInt(100);
    reachLevel = 0;
    while (r >= weights[reachLevel]) {
      r -= weights[reachLevel];
      reachLevel++;
    }
    play(reachLevel >= 2 ? 'hot' : 'reach');
    spinPlayer.setPlaybackRate(0.6); // リーチ中は回転音もゆっくり
  }

  void finish() {
    final r = result.cast<int>();
    final wasReach = reach;
    spinPlayer.stop();
    reach = false;
    chance = false;
    if (r[0] == r[1] && r[1] == r[2]) {
      sinceHit = 0;
      bonusCount++;
      busy = true;
      winNum = r[0];
      Future(() => celebrate(r[0]));
    } else {
      sinceHit++;
      banner = wasReach ? '惜しい!!' : null;
      if (wasReach) play('miss', volume: 0.8);
    }
  }

  Future<void> celebrate(int n) async {
    if (n == 7) {
      await premium();
      return;
    }
    startFx(Fx.win);
    play('win');
    await Future.delayed(const Duration(milliseconds: 1800));
    if (rand.nextInt(3) == 0) {
      // 1/3 で「それでも」昇格
      startFx(Fx.soredemo);
      play('soredemo');
      await Future.delayed(const Duration(milliseconds: 2000));
      setState(() {
        for (int i = 0; i < 3; i++) {
          int t = pos[i].round();
          while (numAt(t) != 7) {
            t++;
          }
          pos[i] = t.toDouble();
          result[i] = 7;
          landKey[i]++;
        }
        winNum = 7;
      });
      await premium();
    } else {
      endFx();
      setState(() => banner = '$n$n$n BONUS!');
    }
  }

  // 白フラッシュ → 金と虹の派手演出
  Future<void> premium() async {
    startFx(Fx.flash);
    play('premium');
    await Future.delayed(const Duration(milliseconds: 220));
    setState(() {
      bonus = true;
      banner = 'UNICORN BONUS!!';
    });
    startFx(Fx.premium);
    final started = fxStart;
    await Future.delayed(const Duration(milliseconds: 5000));
    // タップで先に閉じて次の演出が始まっていたら、そちらは閉じない
    if (fxStart == started) endFx();
  }

  void startFx(Fx next) {
    setState(() {
      fx = next;
      fxStart = DateTime.now();
    });
    if (!fxTicker.isAnimating) fxTicker.repeat();
  }

  void endFx() {
    if (!mounted || fx == Fx.none) return;
    fxTicker.stop();
    setState(() {
      fx = Fx.none;
      busy = false;
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Scaffold(
        backgroundColor: const Color(0xFF140C24),
        appBar: AppBar(
          title: const Text('CR機動戦士ガンダムUC'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 340,
              child: AnimatedBuilder(
                animation: pulse,
                builder: (_, _) => Column(
                  children: [
                    infoBar(),
                    const SizedBox(height: 8),
                    bannerArea(),
                    const SizedBox(height: 8),
                    display(),
                    const SizedBox(height: 14),
                    controlPanel(),
                    const SizedBox(height: 12),
                    const Text(
                      'レバーでスタート → 赤いボタンで1つずつ止める',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      if (fx != Fx.none)
        Positioned.fill(
          child: Material(
            type: MaterialType.transparency,
            child: AnimatedBuilder(
              animation: fxTicker,
              builder: (_, _) => fxLayer(),
            ),
          ),
        ),
    ],
  );

  // ===== 回転数・天井ゲージ =====

  Widget infoBar() {
    final left = ceiling - sinceHit;
    final rate = sinceHit / ceiling;
    final near = left <= 5;
    return Column(
      children: [
        Row(
          children: [
            infoText('回転数 $spins'),
            const Spacer(),
            infoText('BONUS $bonusCount'),
            IconButton(
              tooltip: muted ? '音を出す' : '音を消す',
              icon: Icon(muted ? Icons.volume_off : Icons.volume_up),
              color: Colors.white70,
              visualDensity: VisualDensity.compact,
              onPressed: () {
                setState(() => muted = !muted);
                if (muted) spinPlayer.stop();
              },
            ),
          ],
        ),
        const SizedBox(height: 6),
        Stack(
          children: [
            Container(
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(7),
              ),
            ),
            FractionallySizedBox(
              widthFactor: rate.clamp(0.04, 1.0),
              child: Container(
                height: 14,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF2979FF),
                      Color(0xFFFF1744),
                      Color(0xFFFFD600),
                    ],
                  ),
                  boxShadow: near
                      ? [
                          BoxShadow(
                            color: const Color(
                              0xFFFFD600,
                            ).withValues(alpha: pulse.value),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          near ? 'そろそろ…! 天井まで あと $left 回転' : '天井まで あと $left 回転',
          style: TextStyle(
            color: near
                ? Color.lerp(Colors.white, const Color(0xFFFFD600), pulse.value)
                : Colors.white60,
            fontSize: 12,
            fontWeight: near ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget infoText(String text) => Text(
    text,
    style: const TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.bold,
    ),
  );

  // ===== リーチ・予告・結果の文字 =====

  Widget bannerArea() {
    Widget? child;
    if (reach) {
      child = switch (reachLevel) {
        0 => outlinedText('リーチ', 34, const Color(0xFF64B5F6)),
        1 => outlinedText('リーチ!', 38, const Color(0xFFFF5252)),
        2 => goldText('激アツ!!', 42),
        _ => rainbowText('超激アツ!!', 42, shift: pulse.value),
      };
      if (reachLevel >= 1) {
        child = Transform.scale(scale: 1 + 0.06 * pulse.value, child: child);
      }
    } else if (chance && anySpinning) {
      child = Opacity(
        opacity: 0.5 + 0.5 * pulse.value,
        child: goldText('CHANCE!', 36),
      );
    } else if (banner != null) {
      child = banner == '惜しい!!'
          ? outlinedText(banner!, 34, const Color(0xFFFFAB40))
          : bonus
          ? rainbowText(banner!, 30, shift: pulse.value)
          : goldText(banner!, 32);
    }
    return SizedBox(
      height: 56,
      child: Center(child: child == null ? null : FittedBox(child: child)),
    );
  }

  // ===== 数字図柄 =====

  Widget display() {
    final hot = reach && reachLevel >= 1;
    final frameColor = bonus
        ? const Color(0xFFFFB300)
        : hot
        ? Color.lerp(
            const Color(0xFFFF1744),
            const Color(0xFFFFD600),
            pulse.value,
          )!
        : chance && anySpinning
        ? const Color(0xFFFFD54F)
        : Colors.white24;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: frameColor, width: 3),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: hot
              ? const [Color(0xFF4A0000), Color(0xFF1A0000)]
              : const [Color(0xFF1B1B3A), Color(0xFF0B0B1A)],
        ),
        boxShadow: hot || bonus
            ? [BoxShadow(color: frameColor, blurRadius: 18 * pulse.value + 6)]
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [column(0), column(1), column(2)],
      ),
    );
  }

  Widget column(int i) {
    final p = pos[i];
    final base = p.floor();
    final frac = p - base;
    final isReachCol = reach && spinning[i] && i == reachColumn;
    Widget content;
    if (!spinning[i]) {
      final n = result[i] ?? numAt(base);
      content = TweenAnimationBuilder<double>(
        key: ValueKey('$i-${landKey[i]}'),
        tween: Tween(begin: 1.25, end: 1),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        builder: (_, s, child) => Transform.scale(scale: s, child: child),
        child: stoppedTile(i, n),
      );
    } else {
      final fast = !isReachCol && target[i] == null;
      content = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 0, sigmaY: fast ? 3 : 0),
        child: Stack(
          children: [
            Positioned(
              top: frac * tileH,
              left: 0,
              right: 0,
              height: tileH,
              child: rollingTile(numAt(base)),
            ),
            Positioned(
              top: (frac - 1) * tileH,
              left: 0,
              right: 0,
              height: tileH,
              child: rollingTile(numAt(base + 1)),
            ),
          ],
        ),
      );
    }
    return Container(
      width: tileW,
      height: tileH,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: isReachCol
            ? Border.all(
                color: Color.lerp(
                  const Color(0xFFFF1744),
                  const Color(0xFFFFD600),
                  pulse.value,
                )!,
                width: 3,
              )
            : null,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: content),
    );
  }

  // 回転中：色付きのタイルに数字
  Widget rollingTile(int n) => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [tileColors[n - 1], Colors.black],
      ),
    ),
    alignment: Alignment.center,
    child: numberGlyph(n, 72),
  );

  // 停止後：バナージの画像の上に大きな数字
  Widget stoppedTile(int i, int n) => Stack(
    fit: StackFit.expand,
    children: [
      Image.network(
        bonus && n == 7 ? rareImages[i] : images[n - 1],
        fit: BoxFit.cover,
        // CORS のない画像サーバーでも <img> で表示できるようにする
        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
        errorBuilder: (_, _, _) => rollingTile(n),
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0xAA000000)],
          ),
        ),
      ),
      Align(
        alignment: const Alignment(0, 0.55),
        child: numberGlyph(n, 76, glow: bonus && n == 7),
      ),
    ],
  );

  // ===== 筐体 =====

  // 赤い筐体：左にレバー、白いパネルにストップボタン3つ
  Widget controlPanel() => Container(
    padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFE53935), Color(0xFFB71C1C), Color(0xFF7F0000)],
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      children: [
        lever(),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(40),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [stopButton(0), stopButton(1), stopButton(2)],
            ),
          ),
        ),
      ],
    ),
  );

  Widget lever() => GestureDetector(
    onTap: pull,
    child: SizedBox(
      width: 56,
      height: 96,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: Alignment(-0.4, -0.5),
                colors: [Color(0xFF777777), Colors.black],
              ),
              boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 6)],
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 8,
            height: leverDown ? 10 : 34,
            color: const Color(0xFF9E9E9E),
          ),
          Container(
            width: 40,
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFF212121),
              borderRadius: BorderRadius.circular(7),
            ),
          ),
        ],
      ),
    ),
  );

  Widget stopButton(int i) {
    final active = spinning[i] && result[i] == null;
    return GestureDetector(
      onTap: () => stop(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF5D0000), width: 3),
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.4),
            colors: active
                ? const [
                    Color(0xFFFF8A80),
                    Color(0xFFE53935),
                    Color(0xFF8E0000),
                  ]
                : const [
                    Color(0xFFB36060),
                    Color(0xFF7A2626),
                    Color(0xFF4A1010),
                  ],
          ),
          boxShadow: active
              ? const [BoxShadow(color: Color(0xB3FF5252), blurRadius: 12)]
              : null,
        ),
      ),
    );
  }

  // ===== 全画面演出 =====

  Widget fxLayer() {
    final ms = DateTime.now().difference(fxStart).inMilliseconds;
    final t = ms / 1000;
    switch (fx) {
      case Fx.win:
        // そろった！金色の光線
        final s = Curves.elasticOut.transform(min(t / 0.9, 1.0));
        return Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: RaysPainter(
                angle: t * 0.8,
                colors: const [
                  Color(0xFFFFD54F),
                  Color(0xFFFF9800),
                  Color(0xFFFFF59D),
                ],
                background: const Color(0xE6200F00),
              ),
            ),
            CustomPaint(painter: SparklePainter(t)),
            Center(
              child: FittedBox(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.scale(
                        scale: 0.3 + 0.7 * s,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            numberGlyph(winNum, 96),
                            const SizedBox(width: 16),
                            numberGlyph(winNum, 96),
                            const SizedBox(width: 16),
                            numberGlyph(winNum, 96),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      goldText('BONUS!!', 52),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      case Fx.soredemo:
        // 黒地に虹のネオン光線、虹色の「それでも!」が点滅
        final punch = 1 + 0.8 * pow(1 - min(t / 0.25, 1), 2);
        final visible = ms < 300 || ms % 200 < 140;
        final shake = Offset(sin(t * 90) * 4, cos(t * 70) * 4);
        return Transform.translate(
          offset: shake,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                painter: RaysPainter(
                  angle: t * 0.5,
                  colors: rainbow,
                  background: const Color(0xF2000000),
                  count: 28,
                ),
              ),
              Center(
                child: Opacity(
                  opacity: visible ? 1 : 0.35,
                  child: Transform.scale(
                    scale: punch.toDouble(),
                    child: Transform.rotate(
                      angle: -0.08,
                      child: FittedBox(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: rainbowText('それでも!', 120, shift: t * 0.3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      case Fx.flash:
        return const ColoredBox(color: Colors.white);
      case Fx.premium:
        return GestureDetector(onTap: endFx, child: premiumLayer(t));
      case Fx.none:
        return const SizedBox.shrink();
    }
  }

  // 金と虹が回る「脳汁」演出
  Widget premiumLayer(double t) {
    final shake = t < 0.7
        ? Offset(sin(t * 120) * 10 * (0.7 - t), cos(t * 95) * 10 * (0.7 - t))
        : Offset.zero;
    final shift = (t * 8).floor();
    final rayColors = [
      for (int i = 0; i < 14; i++)
        i.isEven
            ? const Color(0xFFFFD54F)
            : rainbow[(i ~/ 2 + shift) % rainbow.length],
    ];
    final sevenScale = Curves.elasticOut.transform(min(t / 1.1, 1.0));
    final textScale = Curves.easeOutBack.transform(
      ((t - 0.5) / 0.5).clamp(0.0, 1.0),
    );
    final whiteOut = (1 - t / 0.35).clamp(0.0, 1.0);
    return Transform.translate(
      offset: shake,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            painter: RaysPainter(
              angle: t * 1.4,
              colors: rayColors,
              background: const Color(0xFF2A1400),
              count: 28,
            ),
          ),
          CustomPaint(painter: SparklePainter(t)),
          Center(
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 48,
                  vertical: 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: 0.2 + 0.8 * sevenScale,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LuxurySeven(size: 84, glow: true),
                          SizedBox(width: 16),
                          LuxurySeven(size: 84, glow: true),
                          SizedBox(width: 16),
                          LuxurySeven(size: 84, glow: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),
                    Transform.scale(
                      scale: textScale,
                      child: rainbowText('UNICORN BONUS', 44, shift: t * 0.8),
                    ),
                    const SizedBox(height: 12),
                    Opacity(
                      opacity: (t * 2 % 2 < 1.4) ? 0.9 : 0.3,
                      child: const Text(
                        'タップで閉じる',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (whiteOut > 0)
            IgnorePointer(
              child: ColoredBox(
                color: Colors.white.withValues(alpha: whiteOut),
              ),
            ),
        ],
      ),
    );
  }
}

// ===== 文字と図形の部品 =====

const goldGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0xFFFFF8E1),
    Color(0xFFFFD54F),
    Color(0xFFFF9800),
    Color(0xFFE65100),
  ],
  stops: [0, 0.3, 0.65, 1],
);

// 数字図柄。7 は豪華版、奇数は赤、偶数は青
Widget numberGlyph(int n, double size, {bool glow = false}) {
  if (n == 7) return LuxurySeven(size: size, glow: glow);
  final colors = n.isOdd
      ? const [Color(0xFFFFEBEE), Color(0xFFFF1744), Color(0xFF8E0000)]
      : const [Color(0xFFE3F2FD), Color(0xFF2979FF), Color(0xFF0D2B6B)];
  final style = TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w900,
    fontStyle: FontStyle.italic,
    height: 1,
  );
  return Stack(
    children: [
      Text(
        '$n',
        style: style.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size * 0.2
            ..strokeJoin = StrokeJoin.round
            ..color = Colors.white,
          shadows: [Shadow(color: colors[1], blurRadius: 12)],
        ),
      ),
      Text(
        '$n',
        style: style.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size * 0.12
            ..strokeJoin = StrokeJoin.round
            ..color = Colors.black,
        ),
      ),
      ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ).createShader(r),
        child: Text('$n', style: style.copyWith(color: Colors.white)),
      ),
    ],
  );
}

// 黒フチ＋1色の文字（リーチなど）
Widget outlinedText(String text, double size, Color color) {
  final style = TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w900,
    fontStyle: FontStyle.italic,
    height: 1.1,
  );
  return Stack(
    children: [
      Text(
        text,
        style: style.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size * 0.16
            ..strokeJoin = StrokeJoin.round
            ..color = Colors.black,
          shadows: [Shadow(color: color, blurRadius: 14)],
        ),
      ),
      Text(text, style: style.copyWith(color: color)),
    ],
  );
}

// 黒フチ＋金グラデーションの文字
Widget goldText(String text, double size) {
  final style = TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w900,
    fontStyle: FontStyle.italic,
    height: 1.1,
  );
  return Stack(
    children: [
      Text(
        text,
        style: style.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size * 0.16
            ..strokeJoin = StrokeJoin.round
            ..color = Colors.black,
          shadows: const [Shadow(color: Color(0xFFFF6D00), blurRadius: 16)],
        ),
      ),
      ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => goldGradient.createShader(r),
        child: Text(text, style: style.copyWith(color: Colors.white)),
      ),
    ],
  );
}

// グラデーションを縦にずらして、虹色が流れて見えるようにする
class SlideGradient extends GradientTransform {
  const SlideGradient(this.amount);
  final double amount;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(0, bounds.height * amount, 0);
}

// 虹色の文字。外側に白い光、黒い太フチ、中が虹のグラデーション
Widget rainbowText(String text, double size, {double shift = 0}) {
  final style = TextStyle(
    fontSize: size,
    fontWeight: FontWeight.w900,
    fontStyle: FontStyle.italic,
    height: 1.1,
  );
  return Stack(
    children: [
      Text(
        text,
        style: style.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size * 0.22
            ..strokeJoin = StrokeJoin.round
            ..color = Colors.white,
          shadows: const [
            Shadow(color: Color(0xFFD500F9), blurRadius: 18),
            Shadow(color: Color(0xFF00E5FF), blurRadius: 30),
          ],
        ),
      ),
      Text(
        text,
        style: style.copyWith(
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size * 0.13
            ..strokeJoin = StrokeJoin.round
            ..color = Colors.black,
        ),
      ),
      ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: rainbow,
          tileMode: TileMode.mirror,
          transform: SlideGradient(shift),
        ).createShader(r),
        child: Text(text, style: style.copyWith(color: Colors.white)),
      ),
    ],
  );
}

// 中心から放射状に伸びる光線
class RaysPainter extends CustomPainter {
  RaysPainter({
    required this.angle,
    required this.colors,
    required this.background,
    this.count = 24,
  });
  final double angle;
  final List<Color> colors;
  final Color background;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.longestSide;
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
      ..blendMode = BlendMode.plus;
    for (int i = 0; i < count; i++) {
      final a = angle + i * 2 * pi / count;
      final w = pi / count * 0.55;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + r * cos(a - w), c.dy + r * sin(a - w))
        ..lineTo(c.dx + r * cos(a + w), c.dy + r * sin(a + w))
        ..close();
      canvas.drawPath(
        path,
        paint..color = colors[i % colors.length].withValues(alpha: 0.75),
      );
    }
    // 中心のまぶしい光
    canvas.drawCircle(
      c,
      r * 0.35,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white,
            Colors.white.withValues(alpha: 0.4),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.3, 1],
        ).createShader(Rect.fromCircle(center: c, radius: r * 0.35)),
    );
  }

  @override
  bool shouldRepaint(RaysPainter old) => true;
}

// 画面中にまたたくキラキラ
class SparklePainter extends CustomPainter {
  SparklePainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(7);
    for (int i = 0; i < 80; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final phase = rnd.nextDouble();
      final k = sin((t * 2.5 + phase) * 2 * pi);
      if (k <= 0) continue;
      final s = 4 + 14 * k * rnd.nextDouble();
      final color = i % 3 == 0
          ? Colors.white
          : HSVColor.fromAHSV(1, (i * 47 + t * 240) % 360, 0.5, 1).toColor();
      final p = Path()
        ..moveTo(x, y - s)
        ..quadraticBezierTo(x, y, x + s, y)
        ..quadraticBezierTo(x, y, x, y + s)
        ..quadraticBezierTo(x, y, x - s, y)
        ..quadraticBezierTo(x, y, x, y - s)
        ..close();
      canvas.drawPath(p, Paint()..color = color.withValues(alpha: k));
    }
  }

  @override
  bool shouldRepaint(SparklePainter old) => true;
}

// 豪華な 7 図柄。黒フチ＋金グラデーション＋オレンジの光。
// glow のときは周りを光のリングが回る。
class LuxurySeven extends StatefulWidget {
  const LuxurySeven({super.key, this.size = 56, this.glow = false});
  final double size;
  final bool glow;

  @override
  State<LuxurySeven> createState() => _LuxurySevenState();
}

class _LuxurySevenState extends State<LuxurySeven>
    with SingleTickerProviderStateMixin {
  late final AnimationController ring = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void initState() {
    super.initState();
    if (widget.glow) ring.repeat();
  }

  @override
  void didUpdateWidget(LuxurySeven old) {
    super.didUpdateWidget(old);
    if (widget.glow && !ring.isAnimating) ring.repeat();
    if (!widget.glow) ring.stop();
  }

  @override
  void dispose() {
    ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final style = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      fontStyle: FontStyle.italic,
      height: 1,
    );
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        if (widget.glow)
          AnimatedBuilder(
            animation: ring,
            builder: (_, _) => Stack(
              alignment: Alignment.center,
              children: [
                orbit(size, ring.value * 2 * pi),
                orbit(size, -ring.value * 2 * pi + pi / 3),
              ],
            ),
          ),
        Text(
          '7',
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size * 0.16
              ..strokeJoin = StrokeJoin.round
              ..color = const Color(0xFF1A1A1A),
            shadows: [
              Shadow(
                color: const Color(0xFFFF9100),
                blurRadius: widget.glow ? 24 : 10,
              ),
            ],
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => goldGradient.createShader(r),
          child: Text('7', style: style.copyWith(color: Colors.white)),
        ),
      ],
    );
  }

  // 7 のまわりを回る楕円のリング
  Widget orbit(double size, double angle) => Transform(
    alignment: Alignment.center,
    transform: Matrix4.rotationZ(angle)
      ..multiply(Matrix4.diagonal3Values(1, 0.4, 1)),
    child: Container(
      width: size * 1.6,
      height: size * 1.6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFFFB300), width: 3),
      ),
    ),
  );
}
