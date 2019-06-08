import 'dart:async';

import 'package:tangent/base.dart';
import 'package:tangent/common.dart';
import 'package:tangent/modules/commands.dart';
import 'package:tangent/modules/rpg/data.dart';

class RPGModule extends TangentModule {
  var _saveReq = StreamController<Null>.broadcast();

  void saveTask() async {
    while (loaded) {
      await _saveReq.stream.first;
      await Future.delayed(Duration(milliseconds: 100));

    }
  }

  @override init() async {

  }
}