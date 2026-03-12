import 'package:flutter/material.dart';

import 'package:dice/model.dart';

class ThemeColor {
  final int? themeNumber;
  final BuildContext context;

  ThemeColor({this.themeNumber, required this.context});

  Brightness get _effectiveBrightness {
    switch (themeNumber) {
      case 1:
        return Brightness.light;
      case 2:
        return Brightness.dark;
      default:
        return Theme.of(context).brightness;
    }
  }

  Color _getRainbowAccentColor(int hue, double saturation, double value) {
    return HSVColor.fromAHSV(1.0, hue.toDouble(), saturation, value).toColor();
  }

  bool get _isLight => _effectiveBrightness == Brightness.light;

  Color get mainBackColor => _isLight ? _getRainbowAccentColor(Model.schemeColor,1,0.4) : _getRainbowAccentColor(Model.schemeColor,1,0.1);
  Color get mainBack2Color => _isLight ? _getRainbowAccentColor(Model.schemeColor,1,0.8) : _getRainbowAccentColor(Model.schemeColor,1,0.4);
  Color get mainForeColor => _isLight ? Color.fromRGBO(255, 255, 255, 0.5) : Color.fromRGBO(255, 255, 255, 0.3);
  //
  Color get backColor => _isLight ? Colors.grey[200]! : Colors.grey[900]!;
  Color get cardColor => _isLight ? Colors.white : Colors.grey[800]!;
  Color get appBarForegroundColor => _isLight ? Colors.grey[700]! : Colors.white70;
  Color get dropdownColor => cardColor;
  Color get backColorMono => _isLight ? Colors.white : Colors.black;
  Color get foreColorMono => _isLight ? Colors.black : Colors.white;

}
