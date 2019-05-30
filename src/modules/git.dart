import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../main.dart';

class GitModule extends TangentModule {
  WebSocket ws;

  var events = StreamController.broadcast();

  Future init() async {
    print("Connecting to webhook collector...");
    ws = await WebSocket.connect("wss://me.tst.sh/tangent-webhook/ws");
    ws.add(jsonEncode({"secret": await File("tokens/webhook_collector.txt").readAsString()}));
    ws.listen((dataText) {
      if (dataText is String) {
        var data = jsonDecode(dataText) as List;
        events.addStream(Stream.fromIterable(data));
      }
    });
  }

  onReady() async {
    await for (var ev in events.stream) {
      try {
        print(JsonEncoder.withIndent("  ").convert(ev));
        await Future.delayed(Duration(seconds: 5));
      } catch (e, bt) {
        stderr.writeln(e);
        stderr.writeln(bt);
      }
    }
  }
}