import 'dart:ui' as ui;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dice/l10n/app_localizations.dart';

class Model {
  Model._();

  static const String _prefObjectNumber = 'objectNumber';
  static const String _prefDiceCount = 'diceCount';
  static const String _prefCountdownTime = 'countdownTime';
  static const String _prefSoundThrowVolume = 'soundThrowVolume';
  static const String _prefSoundRollingVolume = 'soundRollingVolume';
  static const String _prefSchemeColor = 'schemeColor';
  static const String _prefThemeNumber = 'themeNumber';
  static const String _prefLanguageCode = 'languageCode';

  static bool _ready = false;
  static int _objectNumber = 0;
  static int _diceCount = 1;
  static int _countdownTime = 0;
  static double _soundThrowVolume = 0.5;
  static double _soundRollingVolume = 0.5;
  static int _schemeColor = 120;
  static int _themeNumber = 0;
  static String _languageCode = '';

  static int get objectNumber => _objectNumber;
  static int get diceCount => _diceCount;
  static int get countdownTime => _countdownTime;
  static double get soundThrowVolume => _soundThrowVolume;
  static double get soundRollingVolume => _soundRollingVolume;
  static int get schemeColor => _schemeColor;
  static int get themeNumber => _themeNumber;
  static String get languageCode => _languageCode;

  static Future<void> ensureReady() async {
    if (_ready) {
      return;
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    //
    _objectNumber = (prefs.getInt(_prefObjectNumber) ?? 0).clamp(0,4);
    _diceCount = (prefs.getInt(_prefDiceCount) ?? 1).clamp(1,6);
    _countdownTime = (prefs.getInt(_prefCountdownTime) ?? 0).clamp(0,9);
    _soundThrowVolume = (prefs.getDouble(_prefSoundThrowVolume) ?? 0.5).clamp(0.0,1.0);
    _soundRollingVolume = (prefs.getDouble(_prefSoundRollingVolume) ?? 0.5).clamp(0.0,1.0);
    _schemeColor = (prefs.getInt(_prefSchemeColor) ?? 120).clamp(0, 360);
    _themeNumber = (prefs.getInt(_prefThemeNumber) ?? 0).clamp(0, 2);
    _languageCode = prefs.getString(_prefLanguageCode) ?? ui.PlatformDispatcher.instance.locale.languageCode;
    _languageCode = _resolveLanguageCode(_languageCode);
    _ready = true;
  }

  static String _resolveLanguageCode(String code) {
    final supported = AppLocalizations.supportedLocales;
    if (supported.any((l) => l.languageCode == code)) {
      return code;
    } else {
      return '';
    }
  }

  static Future<void> setObjectNumber(int value) async {
    _objectNumber = value;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefObjectNumber, value);
  }

  static Future<void> setDiceCount(int value) async {
    _diceCount = value;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefDiceCount, value);
  }

  static Future<void> setCountdownTime(int value) async {
    _countdownTime = value;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefCountdownTime, value);
  }

  static Future<void> setSoundThrowVolume(double value) async {
    _soundThrowVolume = value;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefSoundThrowVolume, value);
  }

  static Future<void> setSoundRollingVolume(double value) async {
    _soundRollingVolume = value;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefSoundRollingVolume, value);
  }

  static Future<void> setSchemeColor(int value) async {
    _schemeColor = value;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefSchemeColor, value);
  }

  static Future<void> setThemeNumber(int value) async {
    _themeNumber = value;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefThemeNumber, value);
  }

  static Future<void> setLanguageCode(String value) async {
    _languageCode = value;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLanguageCode, value);
  }

}
