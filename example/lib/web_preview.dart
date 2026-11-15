import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:cocoverse_ui/cocoverse_ui.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'gaze_onboarding.dart';

// One Flutter engine for the whole website. Every phone on the page is its
// own view of it, and only the phone that is awake animates.

/// Which views are awake, by view id.
final Map<int, ValueNotifier<bool>> _awake = <int, ValueNotifier<bool>>{};

ValueNotifier<bool> _awakeFor(int viewId) =>
    _awake.putIfAbsent(viewId, () => ValueNotifier<bool>(false));

/// Called by the website: wakes a phone or puts it to sleep.
void _setAwake(JSNumber viewId, JSBoolean on) {
  _awakeFor(viewId.toDartInt).value = on.toDart;
}

void main() {
  globalContext.setProperty('cocoverseSetActive'.toJS, _setAwake.toJS);
  runWidget(
    MultiViewApp(
      viewBuilder: (context) => _PhoneView(viewId: View.of(context).viewId),
    ),
  );
}

/// Keeps one widget tree per view as the page adds and removes them.
class MultiViewApp extends StatefulWidget {
  const MultiViewApp({super.key, required this.viewBuilder});

  final WidgetBuilder viewBuilder;

  @override
  State<MultiViewApp> createState() => _MultiViewAppState();
}

class _MultiViewAppState extends State<MultiViewApp>
    with WidgetsBindingObserver {
  Map<Object, Widget> _views = <Object, Widget>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateViews();
  }

  @override
  void didChangeMetrics() {
    _updateViews();
  }

  void _updateViews() {
    final newViews = <Object, Widget>{};
    for (final ui.FlutterView view
        in WidgetsBinding.instance.platformDispatcher.views) {
      newViews[view.viewId] = _views[view.viewId] ?? _createViewWidget(view);
    }
    setState(() {
      _views = newViews;
    });
  }

  Widget _createViewWidget(ui.FlutterView view) {
    return View(view: view, child: Builder(builder: widget.viewBuilder));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ViewCollection(views: _views.values.toList(growable: false));
  }
}

class _PhoneView extends StatelessWidget {
  const _PhoneView({required this.viewId});

  final int viewId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: _EffectView(viewId: viewId),
      ),
    );
  }
}

String? _stringOf(JSAny? v) => v.isA<JSString>() ? (v as JSString).toDart : null;

bool? _boolOf(JSAny? v) => v.isA<JSBoolean>() ? (v as JSBoolean).toDart : null;

/// The Gaze phone. It shows the eye, and after five seconds of being awake it shows the
/// onboarding screen that uses it, then goes back to the eye after ten more seconds awake.
/// The clock only runs while the phone is awake, so a sleeping phone keeps what it shows.
class _GazeShowcase extends StatefulWidget {
  const _GazeShowcase({required this.awake});

  final ValueNotifier<bool> awake;

  @override
  State<_GazeShowcase> createState() => _GazeShowcaseState();
}

class _GazeShowcaseState extends State<_GazeShowcase> {
  static const int _eyeSeconds = 5;
  static const int _caseSeconds = 10;

  Timer? _timer;
  int _seconds = 0;
  bool _showCase = false;

  @override
  void initState() {
    super.initState();
    widget.awake.addListener(_onAwake);
    _onAwake();
  }

  void _onAwake() {
    _timer?.cancel();
    _timer = null;
    if (!widget.awake.value) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _seconds++;
      if (_seconds < (_showCase ? _caseSeconds : _eyeSeconds)) return;
      _seconds = 0;
      if (mounted) setState(() => _showCase = !_showCase);
    });
  }

  @override
  void dispose() {
    widget.awake.removeListener(_onAwake);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF111111),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [...previous, if (current != null) current],
        ),
        child: _showCase
            ? const GazeOnboarding(key: ValueKey('gaze-case'))
            : const Gaze(key: ValueKey('gaze-eye')),
      ),
    );
  }
}

class _EffectView extends StatefulWidget {
  const _EffectView({required this.viewId});

  final int viewId;

  @override
  State<_EffectView> createState() => _EffectViewState();
}

class _EffectViewState extends State<_EffectView> {
  final CharacterController _sprite = CharacterController();
  final ClayBotController _bot = ClayBotController();
  final MitoController _mito = MitoController();
  late final String _slug;
  late final bool _low;
  late final Widget _effect;
  bool _warm = true;

  @override
  void initState() {
    super.initState();
    final data = ui_web.views.getInitialData(widget.viewId) as JSObject?;
    _slug = _stringOf(data?.getProperty<JSAny?>('slug'.toJS)) ?? 'pisces';
    _low = _boolOf(data?.getProperty<JSAny?>('low'.toJS)) ?? false;
    _effect = _buildEffect();

    // Every phone runs for its first two seconds, so its entrance finishes
    // and the frame it freezes on is a good one. Then it tells the page.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _warm = false);
      web.window.dispatchEvent(
        web.CustomEvent(
          'cocoverse-view-ready',
          web.CustomEventInit(detail: widget.viewId.toJS),
        ),
      );
    });
  }

  @override
  void dispose() {
    _sprite.dispose();
    _bot.dispose();
    _mito.dispose();
    super.dispose();
  }

  /// Each effect gets one of three palettes, picked from its name so it is
  /// the same every time.
  List<Color> _paletteFor(String slug) {
    const palettes = <List<Color>>[
      [Color(0xFF7B5CFF), Color(0xFF46D9E8), Color(0xFFFF6FAE)],
      [Color(0xFFE8B64A), Color(0xFF34D1BF), Color(0xFFFF7A59)],
      [Color(0xFF1E8E6A), Color(0xFF34D1BF), Color(0xFF63B7F0)],
    ];
    final sum = slug.codeUnits.fold<int>(0, (a, b) => a + b);
    return palettes[sum % palettes.length];
  }

  Widget _buildEffect() {
    final c = _paletteFor(_slug);
    final quality = _low ? EffectQuality.low : EffectQuality.high;
    return switch (_slug) {
      'glossy-sphere' => GlossySphere(colors: c),
      'starfield-sphere' => StarfieldSphere(),
      'glass-ring' => GlassRing(
          tint: Color.lerp(c[1], const Color(0xFFFFFFFF), 0.5)!,
          backdropText: 'COCO\nVERSE',
          backdropColor: const Color(0xFF080808),
          quality: quality,
        ),
      'particle-cube' => ParticleCube(),
      'shard-sphere' => ShardSphere(colors: c),
      'jelly-sphere' => JellySphere(colors: c),
      'urchin' => Urchin( quality: quality),
      'foil-ring' => FoilRing(colors: c),
      'geo-morph' => GeoMorph(
          color: c[0],
          shapeColors: {
            GeoShape.sphere: c[1],
            GeoShape.octahedron: c[2],
            GeoShape.torus: c[1],
          },
        ),
      'cube-sphere' => CubeSphere(),
      'blossom' => Blossom(),
      'capsule-sprite' => CapsuleSprite(controller: _sprite),
      'clay-bot' => ClayBot(
          controller: _bot,
          walkSpeed: 3.5,
          entrance: ClayBotEntrance.dropIn,
        ),
      'link-chain' => Align(
          alignment: const Alignment(0, -0.2),
          child: SizedBox(
            width: double.infinity,
            height: 170,
            child: LinkChain(
              finish: LinkChainFinish.cartoon,
              metalColor: const Color(0xFFFAD06E),
              slack: 0.14,
              density: 16,
              entrance: false,
              reactToMotion: false,
            ),
          ),
        ),
      'pisces' => Pisces(quality: quality),
      'timeline' => Timeline(
          // The same photos as the example app. The Timeline fills its space, so on the
          // website it fills the whole phone screen, edge to edge.
          images: const [
            AssetImage('assets/photos/one.jpg'),
            AssetImage('assets/photos/two.jpg'),
            AssetImage('assets/photos/three.jpg'),
          ],
          quality: quality,
        ),
      // A shorter bloom, so it has finished by the end of the phone's two-second warm-up.
      'hourglass' => Hourglass(entranceStagger: 2.0, quality: quality),
      'halo' => Halo(tint: const Color(0xFFE8B64A), quality: quality),
            'fireworks' => Fireworks(
          loop: true,
          title: 'Well done!',
          subtitle: 'Your account is ready',
          titleStyle: const TextStyle(fontSize: 30),
          quality: quality,
        ),
      'meteor' => Meteor(
          shape: MeteorShape.plus,
          shapeColor: Color.lerp(c[1], const Color(0xFFFFFFFF), 0.5)!,
          quality: quality,
        ),
      'mito' => Mito(
          controller: _mito,
          entrance: MitoEntrance.powerUp,
          ringGlow: 1.0,
          quality: quality,
        ),
      'moonbloom' => Moonbloom(
          side: MoonbloomSide.right,
          background: const Color(0xFF0A090D),
          quality: quality,
        ),
      'infiloop' => Infiloop(entrance: false, quality: quality),
      'crossfold' => Crossfold(quality: quality),
      'gaze' => _GazeShowcase(awake: _awakeFor(widget.viewId)),
      'plush' => Plush(fur: c[0], background: const Color(0xFF000000)),
      _ => const Center(
          child: Text('Coming soon', style: TextStyle(color: Colors.white54)),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    // A sleeping phone has its tickers switched off, so it costs nothing and
    // keeps showing its last frame. The effect itself is built once and kept.
    return ValueListenableBuilder<bool>(
      valueListenable: _awakeFor(widget.viewId),
      builder: (context, awake, child) =>
          TickerMode(enabled: awake || _warm, child: child!),
      child: _effect,
    );
  }
}

