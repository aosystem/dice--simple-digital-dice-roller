import 'package:just_audio/just_audio.dart';

import 'package:dice/const_value.dart';
import 'package:dice/model.dart';

class AudioPlay {
  static final List<AudioPlayer> _player01 = [
    AudioPlayer(),
    AudioPlayer(),
    AudioPlayer(),
  ];
  static final List<AudioPlayer> _player02 = [
    AudioPlayer(),
    AudioPlayer(),
    AudioPlayer(),
  ];
  int _player01Ptr = 0;
  int _player02Ptr = 0;

  AudioPlay() {
    constructor();
  }
  void constructor() async {
    for (int i = 0; i < _player01.length; i++) {
      await _player01[i].setVolume(0);
      await _player01[i].setAsset(ConstValue.audioSwitch);
    }
    for (int i = 0; i < _player02.length; i++) {
      await _player02[i].setVolume(0);
      await _player02[i].setAsset(ConstValue.audioDice);
    }
    playZero();
  }
  void dispose() {
    for (int i = 0; i < _player01.length; i++) {
      _player01[i].dispose();
    }
    for (int i = 0; i < _player02.length; i++) {
      _player02[i].dispose();
    }
  }

  void playZero() async {
    AudioPlayer ap = AudioPlayer();
    await ap.setAsset(ConstValue.audioZero);
    await ap.load();
    await ap.play();
  }

  void play01() async {
    if (Model.soundThrowVolume == 0) {
      return;
    }
    _player01Ptr += 1;
    if (_player01Ptr >= _player01.length) {
      _player01Ptr = 0;
    }
    await _player01[_player01Ptr].setVolume(Model.soundThrowVolume);
    await _player01[_player01Ptr].pause();
    await _player01[_player01Ptr].seek(const Duration(milliseconds: 100));
    await _player01[_player01Ptr].play();
  }

  void play02() async {
    if (Model.soundRollingVolume == 0) {
      return;
    }
    _player02Ptr += 1;
    if (_player02Ptr >= _player02.length) {
      _player02Ptr = 0;
    }
    await _player02[_player02Ptr].setVolume(Model.soundRollingVolume);
    await _player02[_player02Ptr].pause();
    await _player02[_player02Ptr].seek(Duration.zero);
    await _player02[_player02Ptr].play();
  }
}
