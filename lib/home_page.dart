import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dice/l10n/app_localizations.dart';
import 'package:dice/const_value.dart';
import 'package:dice/setting_page.dart';
import 'package:dice/model.dart';
import 'package:dice/audio_play.dart';
import 'package:dice/ad_manager.dart';
import 'package:dice/ad_banner_widget.dart';
import 'package:dice/parse_locale_tag.dart';
import 'package:dice/theme_color.dart';
import 'package:dice/theme_mode_number.dart';
import 'package:dice/loading_screen.dart';
import 'package:dice/main.dart';

class MainHomePage extends StatefulWidget {
  const MainHomePage({super.key});
  @override
  State<MainHomePage> createState() => _MainHomePageState();
}

class _MainHomePageState extends State<MainHomePage>
    with TickerProviderStateMixin {
  late AdManager _adManager;
  final AudioPlay _audioPlay = AudioPlay();
  late Random _random;
  late ThemeColor _themeColor;
  bool _isBusy = false;
  bool _isReady = false;
  bool _isFirst = true;
  //dice rotation
  late AnimationController _rotateAnimationController;
  late final List<Animation<double>?> _rotateAnimations = [
    null,
    null,
    null,
    null,
    null,
    null,
  ];
  final List<int> _rotateIndex = [0, 1, 2, 3, 4, 5];
  final List<_ImageSequencePlayer?> _imagePlayers = List<_ImageSequencePlayer?>.filled(6, null, growable: false);
  final List<int> _videoIndex = [0, 0, 0, 0, 0, 0];
  Map<String, List<String>>? _frameAssetsByDirectory;
  final Map<String, List<ui.Image>> _decodedFrameCache = <String, List<ui.Image>>{};
  late int _currentObjectNumber;
  static const Duration _frameInterval = Duration(milliseconds: 33);
  static const int _targetFrameExtent = 360;
  int _countdownSubtraction = 0;
  String _imageCountdownNumber = ConstValue.imageNumbers[0];
  double _countdownScale = 3;
  double _countdownOpacity = 0;
  int _timerCount = 30;
  Timer? _timer;
  //dice slide
  late AnimationController _slideAnimationController;
  late Animation<Offset> _slideAnimationOffset;

  @override
  void initState() {
    super.initState();
    _initState();
  }

  @override
  void dispose() {
    _adManager.dispose();
    _timer?.cancel();
    _slideAnimationController.dispose();
    _disposeImagePlayers();
    _clearDecodedFrameCache();
    super.dispose();
  }

  void _initState() async {
    _adManager = AdManager();
    _audioPlay.playZero();
    _random = Random(DateTime.now().millisecondsSinceEpoch);
    //animation
    _rotateAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    for (int i = 0; i < _rotateAnimations.length; i++) {
      double angle = (_random.nextDouble() * 3.14 * 4) - (3.14 * 2);
      _rotateAnimations[i] = Tween<double>(
        begin: 0,
        end: angle,
      ).animate(_rotateAnimationController);
    }
    _rotateAnimationController.addListener(() {
      setState(() {});
    });
    //
    _slideAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _slideAnimationOffset =
        Tween<Offset>(
          begin: const Offset(0, 4),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _slideAnimationController,
            curve: Curves.easeOut,
          ),
        );
    _currentObjectNumber = _resolveModelObjectNumber();
    await _readyAnimations(forceReload: true);
  }

  String? _assetDirectoryForSlot(int slotIndex) {
    if (ConstValue.animationDirectories.isEmpty) {
      return null;
    }
    final int objectNumber = _currentObjectNumber
        .clamp(0, ConstValue.animationDirectories.length - 1)
        .toInt();
    final faces = ConstValue.animationDirectories[objectNumber];
    if (faces.isEmpty) {
      return null;
    }
    final int safeSlot = slotIndex.clamp(0, _videoIndex.length - 1).toInt();
    int faceIndex = _videoIndex[safeSlot];
    if (faceIndex < 0 || faceIndex >= faces.length) {
      faceIndex = 0;
    }
    return faces[faceIndex];
  }

  Future<void> _ensureFrameManifest() async {
    if (_frameAssetsByDirectory != null) {
      return;
    }
    final Map<String, List<String>> frames = <String, List<String>>{};
    bool manifestLoaded = false;
    try {
      final AssetManifest manifest = await AssetManifest.loadFromAssetBundle(
        rootBundle,
      );
      for (final String assetPath in manifest.listAssets()) {
        _addAssetPathToFrames(frames, assetPath);
      }
      manifestLoaded = true;
    } catch (error) {
    }
    if (!manifestLoaded) {
      try {
        final String manifestContent = await rootBundle.loadString(
          'AssetManifest.json',
        );
        final Map<String, dynamic> manifestMap =
            json.decode(manifestContent) as Map<String, dynamic>;
        for (final String assetPath in manifestMap.keys) {
          _addAssetPathToFrames(frames, assetPath);
        }
      } catch (error) {
      }
    }
    for (final List<String> assets in frames.values) {
      assets.sort();
    }
    _frameAssetsByDirectory = frames;
  }

  Future<List<String>> _framesForDirectory(String directory) async {
    await _ensureFrameManifest();
    final List<String>? frames = _frameAssetsByDirectory?[directory];
    return frames == null ? <String>[] : List<String>.from(frames);
  }

  Future<List<ui.Image>> _decodedFramesForDirectory(
    String directory,
    List<String> framePaths,
  ) async {
    final cached = _decodedFrameCache[directory];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final List<ui.Image> decoded = <ui.Image>[];
    for (final String path in framePaths) {
      final ByteData data = await rootBundle.load(path);
      final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: _targetFrameExtent,
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      decoded.add(frame.image);
      codec.dispose();
    }
    _decodedFrameCache[directory] = decoded;
    return decoded;
  }

  int _resolveModelObjectNumber() {
    if (ConstValue.animationDirectories.isEmpty) {
      return 0;
    }
    final int maxIndex = ConstValue.animationDirectories.length - 1;
    return Model.objectNumber.clamp(0, maxIndex).toInt();
  }

  void _disposeImagePlayers() {
    for (int i = 0; i < _imagePlayers.length; i++) {
      _imagePlayers[i]?.dispose();
      _imagePlayers[i] = null;
    }
  }

  void _clearDecodedFrameCache() {
    for (final frames in _decodedFrameCache.values) {
      for (final ui.Image image in frames) {
        image.dispose();
      }
    }
    _decodedFrameCache.clear();
  }

  void _resetVideoIndexes() {
    for (int i = 0; i < _videoIndex.length; i++) {
      _videoIndex[i] = 0;
    }
  }

  Future<void> _precacheObjectDirectories(int objectNumber) async {
    if (ConstValue.animationDirectories.isEmpty) {
      return;
    }
    final int maxIndex = ConstValue.animationDirectories.length - 1;
    final int safeIndex = objectNumber.clamp(0, maxIndex).toInt();
    final List<String> directories = ConstValue.animationDirectories[safeIndex];
    final Set<String> seen = <String>{};
    for (final String directory in directories) {
      if (!seen.add(directory)) {
        continue;
      }
      final frames = await _framesForDirectory(directory);
      if (frames.isEmpty) {
        continue;
      }
      await _decodedFramesForDirectory(directory, frames);
    }
  }

  void _addAssetPathToFrames(
    Map<String, List<String>> frames,
    String assetPath,
  ) {
    if (!assetPath.startsWith('assets/image/')) {
      return;
    }
    if (!(assetPath.endsWith('.png') || assetPath.endsWith('.webp'))) {
      return;
    }
    final int lastSlash = assetPath.lastIndexOf('/');
    if (lastSlash <= 0) {
      return;
    }
    final String directory = assetPath.substring(0, lastSlash);
    frames.putIfAbsent(directory, () => <String>[]).add(assetPath);
  }

  Future<_ImageSequencePlayer?> _createImagePlayer(int slotIndex) async {
    final directory = _assetDirectoryForSlot(slotIndex);
    if (directory == null) {
      return null;
    }
    final frames = await _framesForDirectory(directory);
    if (frames.isEmpty) {
      return null;
    }
    final decodedFrames = await _decodedFramesForDirectory(directory, frames);
    if (decodedFrames.isEmpty) {
      return null;
    }
    return _ImageSequencePlayer(
      frames: decodedFrames,
      frameInterval: _frameInterval,
      vsync: this,
    );
  }

  Future<void> _recreateImagePlayers({
    Iterable<int>? targetIndexes,
    bool triggerSetState = true,
  }) async {
    final List<int> indexes;
    if (targetIndexes == null || targetIndexes.isEmpty) {
      indexes = List<int>.generate(_imagePlayers.length, (i) => i);
    } else {
      final unique = <int>{};
      for (final index in targetIndexes) {
        if (index >= 0 && index < _imagePlayers.length) {
          unique.add(index);
        }
      }
      indexes = unique.toList();
    }
    if (indexes.isEmpty) {
      return;
    }
    bool updated = false;
    final List<_ImageSequencePlayer> disposables = <_ImageSequencePlayer>[];
    for (final index in indexes) {
      final previous = _imagePlayers[index];
      if (previous != null) {
        disposables.add(previous);
        _imagePlayers[index] = null;
        updated = true;
      }
      final player = await _createImagePlayer(index);
      if (player == null) {
        continue;
      }
      _imagePlayers[index] = player;
      updated = true;
    }
    if (triggerSetState && mounted && updated) {
      setState(() {});
    }
    for (final disposable in disposables) {
      disposable.dispose();
    }
  }

  Future<void> _readyAnimations({bool forceReload = false}) async {
    final int latestObject = _resolveModelObjectNumber();
    final bool objectChanged = latestObject != _currentObjectNumber;
    final bool shouldReload = forceReload || objectChanged || !_isReady;
    if (!shouldReload) {
      return;
    }
    if (mounted) {
      setState(() {
        _isReady = false;
      });
    } else {
      _isReady = false;
    }
    if (objectChanged || forceReload) {
      _currentObjectNumber = latestObject;
      _resetVideoIndexes();
      _disposeImagePlayers();
      _clearDecodedFrameCache();
    }
    if (ConstValue.animationDirectories.isNotEmpty) {
      await _precacheObjectDirectories(latestObject);
    }
    _currentObjectNumber = latestObject;
    await _recreateImagePlayers(triggerSetState: false);
    if (!mounted) {
      return;
    }
    setState(() {
      _isReady = true;
    });
  }

  void _updateSlideOffset(TapDownDetails details) {
    final Offset localPosition = details.localPosition;
    double x = (localPosition.dx - (context.size!.width / 2)) / context.size!.width;
    double y = (localPosition.dy - (context.size!.height / 2)) / context.size!.height;
    if (x < -0.1) {
      x = -2;
    } else if (x > 0.1) {
      x = 2;
    }
    if (y < -0.1) {
      y = -2;
    } else if (y > 0.1) {
      y = 2;
    }
    if (x > -2 && x < 2 && y > -2 && y < 2) {
      x *= 20;
      y *= 20;
    }
    final Offset begin = Offset(x, y);
    _slideAnimationOffset = Tween<Offset>(begin: begin, end: Offset.zero)
      .animate(
        CurvedAnimation(
          parent: _slideAnimationController,
          curve: Curves.easeOut,
        ),
      );
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SettingPage()),
    );
    if (!mounted) {
      return;
    }
    if (updated == true) {
      final mainState = context.findAncestorStateOfType<MainAppState>();
      if (mainState != null) {
        mainState
          ..themeMode = ThemeModeNumber.numberToThemeMode(Model.themeNumber)
          ..locale = parseLocaleTag(Model.languageCode)
          ..setState(() {});
      }
      await _readyAnimations(forceReload: true);
      _isFirst = true;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_isReady == false) {
      return const LoadingScreen();
    }
    if (_isFirst) {
      _isFirst = false;
      _themeColor = ThemeColor(context: context);
      _diceAction();
    }
    final AppLocalizations l = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: _themeColor.mainBack2Color,
      body: Stack(children:[
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_themeColor.mainBack2Color, _themeColor.mainBackColor],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            image: DecorationImage(
              image: AssetImage('assets/image/tile.png'),
              repeat: ImageRepeat.repeat,
              opacity: 0.1,
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              Opacity(
                opacity: _isBusy ? 0.2 : 1,
                child: SizedBox(
                  height: 48,
                  child: Stack(
                    children: [
                      Center(
                        child: Text(
                          l.start,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _themeColor.mainForeColor,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                      ),
                      Positioned(right: 10, top: 0, bottom: 0,
                        child: Center(
                          child: IconButton(
                            onPressed: _openSettings,
                            tooltip: l.setting,
                            icon: const Icon(Icons.settings),
                            color: _themeColor.mainForeColor,
                          ),
                        )
                      ),
                    ],
                  )
                )
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (TapDownDetails details) {
                    _onClickStart(details);
                  },
                  child: Stack(
                    children: [
                      Center(child: _diceArea()),
                      Center(
                        child: Opacity(
                          opacity: _countdownOpacity,
                          child: Transform.scale(
                            scale: _countdownScale,
                            child: Image.asset(_imageCountdownNumber),
                          )
                        )
                      )
                    ]
                  )
                )
              )
            ]
          )
        )
      ]),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(color: _themeColor.mainBackColor),
        child: AdBannerWidget(adManager: _adManager),
      ),
    );
  }

  void _timerStart() {
    _timer = Timer.periodic(const Duration(milliseconds: (1000 ~/ 30)), (
      timer,
    ) {
      setState(() {
        _countdown();
      });
    });
  }

  void _onClickStart(TapDownDetails details) {
    if (_isBusy) {
      return;
    }
    _isBusy = true;
    _updateSlideOffset(details);
    _countdownSubtraction = Model.countdownTime;
    if (_countdownSubtraction == 0) {
      _diceAction();
    } else {
      _audioPlay.play01();
      _timerStart();
    }
  }

  void _diceAction() async {
    if (!_isReady) {
      setState(() {
        _isBusy = false;
      });
      return;
    }
    final int latestObjectNumber = _resolveModelObjectNumber();
    if (latestObjectNumber != _currentObjectNumber) {
      await _readyAnimations(forceReload: true);
      if (!_isReady) {
        setState(() {
          _isBusy = false;
        });
        return;
      }
    }
    _slideAnimationController.reset();
    _slideAnimationController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _slideAnimationController.value = 0.0;
      });
      _slideAnimationController.forward();
    });
    //
    _audioPlay.play02();
    //
    _rotateAnimationController.reset();
    _rotateIndex.shuffle();
    _rotateAnimationController.forward();
    //
    if (ConstValue.animationDirectories.isEmpty) {
      setState(() {
        _isBusy = false;
      });
      return;
    }
    final int objectIndex = _currentObjectNumber
        .clamp(0, ConstValue.animationDirectories.length - 1)
        .toInt();
    final faces = ConstValue.animationDirectories[objectIndex];
    if (faces.isEmpty || Model.diceCount == 0) {
      setState(() {
        _isBusy = false;
      });
      return;
    }
    final nextFaces = List<int>.generate(
      Model.diceCount,
      (_) => _random.nextInt(faces.length),
    );
    for (int i = 0; i < Model.diceCount; i++) {
      _videoIndex[i] = nextFaces[i];
    }
    final slotIndexes = List<int>.generate(Model.diceCount, (i) => i);
    await _recreateImagePlayers(
      targetIndexes: slotIndexes,
      triggerSetState: false,
    );
    if (!mounted) {
      return;
    }
    setState(() {});
    for (final slotIndex in slotIndexes) {
      _playImageSequence(slotIndex);
    }
    Future.delayed(const Duration(milliseconds: 2000)).then(
      (_) => {
        setState(() {
          _isBusy = false;
        }),
      },
    );
  }

  void _playImageSequence(int index) {
    if (index < 0 || index >= _imagePlayers.length) {
      return;
    }
    final player = _imagePlayers[index];
    if (player == null) {
      return;
    }
    final speed = 0.8 + (_random.nextDouble() * 0.4);
    player.play(speedMultiplier: speed);
  }

  void _countdown() {
    if (_countdownSubtraction == 0) {
      return;
    }
    if (_timerCount == 30) {
      _imageCountdownNumber = ConstValue.imageNumbers[_countdownSubtraction];
    }
    _timerCount -= 1;
    if (_timerCount <= 0) {
      _timerCount = 30;
      _countdownSubtraction -= 1;
      if (_countdownSubtraction == 0) {
        _imageCountdownNumber = ConstValue.imageNumbers[0];
        _timer?.cancel();
        _diceAction();
      }
    }
    _countdownScale = 1 + (0.1 * (_timerCount / 30));
    if (_timerCount >= 20) {
      _countdownOpacity = (30 - _timerCount) / 10;
    } else if (_timerCount <= 5) {
      _countdownOpacity = _timerCount / 5;
    } else {
      _countdownOpacity = 1;
    }
  }

  Widget _diceArea() {
    if (Model.diceCount == 1) {
      return _objectOne(0);
    } else if (Model.diceCount == 2) {
      return AspectRatio(
        aspectRatio: 1 / 2,
        child: Column(
          children: [
            Expanded(child: _objectOne(0)),
            Expanded(child: _objectOne(1)),
          ],
        ),
      );
    } else if (Model.diceCount == 3) {
      return AspectRatio(
        aspectRatio: 1,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [_objectOneExpanded(0), _objectOneExpanded(1)],
              ),
            ),
            Expanded(child: _objectOne(2)),
          ],
        ),
      );
    } else if (Model.diceCount == 4) {
      return AspectRatio(
        aspectRatio: 1,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [_objectOneExpanded(0), _objectOneExpanded(1)],
              ),
            ),
            Expanded(
              child: Row(
                children: [_objectOneExpanded(2), _objectOneExpanded(3)],
              ),
            ),
          ],
        ),
      );
    } else if (Model.diceCount == 5) {
      return AspectRatio(
        aspectRatio: 2 / 3,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [_objectOneExpanded(0), _objectOneExpanded(1)],
              ),
            ),
            Expanded(
              child: Row(
                children: [_objectOneExpanded(2), _objectOneExpanded(3)],
              ),
            ),
            Expanded(child: _objectOne(4)),
          ],
        ),
      );
    } else if (Model.diceCount == 6) {
      return AspectRatio(
        aspectRatio: 2 / 3,
        child: Column(
          children: [
            Expanded(
              child: Row(
                children: [_objectOneExpanded(0), _objectOneExpanded(1)],
              ),
            ),
            Expanded(
              child: Row(
                children: [_objectOneExpanded(2), _objectOneExpanded(3)],
              ),
            ),
            Expanded(
              child: Row(
                children: [_objectOneExpanded(4), _objectOneExpanded(5)],
              ),
            ),
          ],
        ),
      );
    }
    return Container();
  }

  Widget _objectOne(int index) {
    return SlideTransition(
      position: _slideAnimationOffset,
      child: ClipOval(
        child: Transform.rotate(
          angle: _rotateAnimations[_rotateIndex[index]]!.value,
          child: AspectRatio(aspectRatio: 1, child: _buildImageForSlot(index)),
        ),
      ),
    );
  }

  Widget _objectOneExpanded(int index) {
    return Expanded(
      child: Center(
        child: SlideTransition(
          position: _slideAnimationOffset,
          child: ClipOval(
            child: Transform.rotate(
              angle: _rotateAnimations[_rotateIndex[index]]!.value,
              child: AspectRatio(
                aspectRatio: 1,
                child: _buildImageForSlot(index),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageForSlot(int index) {
    if (index < 0 || index >= _imagePlayers.length) {
      return const SizedBox.expand();
    }
    final player = _imagePlayers[index];
    if (player == null) {
      return const SizedBox.expand();
    }
    return ValueListenableBuilder<int>(
      valueListenable: player.frameIndexListenable,
      builder: (BuildContext context, int frameIndex, _) {
        final ui.Image? image = player.imageForFrame(frameIndex);
        if (image == null) {
          return const SizedBox.expand();
        }
        return RawImage(
          image: image,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        );
      },
    );
  }
}

class _ImageSequencePlayer {
  _ImageSequencePlayer({
    required List<ui.Image> frames,
    required Duration frameInterval,
    required TickerProvider vsync,
  }) : assert(frames.isNotEmpty),
       _frames = frames,
       _frameInterval = frameInterval,
       frameIndexListenable = ValueNotifier<int>(0),
       _controller = AnimationController(
         vsync: vsync,
         duration: Duration(
           microseconds: frameInterval.inMicroseconds * frames.length,
         ),
       ) {
    _controller.addListener(_handleTick);
    _statusListener = (AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        _controller.stop();
        if (_frames.isNotEmpty) {
          _currentFrame = _frames.length - 1;
          frameIndexListenable.value = _currentFrame;
        }
      }
    };
    _controller.addStatusListener(_statusListener);
  }

  final List<ui.Image> _frames;
  final Duration _frameInterval;
  final AnimationController _controller;
  final ValueNotifier<int> frameIndexListenable;
  late final AnimationStatusListener _statusListener;
  int _currentFrame = 0;

  void play({double speedMultiplier = 1.0}) {
    if (_frames.isEmpty) {
      return;
    }
    final double clampedSpeed = speedMultiplier.clamp(0.1, 3.0);
    _controller.stop();
    _controller.duration = _durationForSpeed(clampedSpeed);
    _currentFrame = 0;
    frameIndexListenable.value = _currentFrame;
    _controller.value = 0;
    _controller.forward();
  }

  void dispose() {
    _controller.removeListener(_handleTick);
    _controller.removeStatusListener(_statusListener);
    _controller.dispose();
    frameIndexListenable.dispose();
  }

  ui.Image? imageForFrame(int frameIndex) {
    if (_frames.isEmpty) {
      return null;
    }
    final int clamped = frameIndex.clamp(0, _frames.length - 1);
    return _frames[clamped];
  }

  void _handleTick() {
    if (_frames.isEmpty) {
      return;
    }
    final int nextFrame = (_controller.value * _frames.length).floor().clamp(
      0,
      _frames.length - 1,
    );
    if (nextFrame != _currentFrame) {
      _currentFrame = nextFrame;
      frameIndexListenable.value = _currentFrame;
    }
  }

  Duration _durationForSpeed(double speedMultiplier) {
    final double totalMicros =
        (_frameInterval.inMicroseconds * _frames.length) / speedMultiplier;
    final int clampedMicros = totalMicros.clamp(1000.0, 60000000.0).round();
    return Duration(microseconds: clampedMicros);
  }
}
