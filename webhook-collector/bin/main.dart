import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import 'dart:isolate';


main() async {
  var allowedKeys = LineSplitter().convert((await File("tokens/allowed.txt").readAsString()).trim());
  var secret = (await File("tokens/secret.txt").readAsString()).trim();
  await runZoned(() async {
    var server = await HttpServer.listenOn(await ServerSocket.bind("127.0.0.1", 5959));
    var queue = [];
    WebSocket client;
    server.listen((req) async {
      print("[${req.method}] ${req.uri.path}");
      if (req.uri.path == "/tangent-webhook") {
        var reqdata = await req.expand((e) => e).toList();
        var sig = req.headers.value("X-Hub-Signature");
        bool valid = false;
        for (var k in allowedKeys) {
          var hmac = new Hmac(sha1, Utf8Codec().encode(k));
          var res = "sha1=" + hmac.convert(reqdata).toString();
          if (sig == res) {
            valid = true;

            break;
          }
        }

        if (!valid) {
          req.response.statusCode = 500;
          await req.response.close();
          return;
        }

        var data = jsonDecode(Utf8Codec().decode(reqdata));

        data["event-type"] = req.headers.value("X-GitHub-Event");

        print("got data! ${JsonEncoder.withIndent("  ").convert(data)}");

        queue.add(data);
        if (client != null) {
          client.add(jsonEncode(queue));
          queue.clear();
        }
        req.response.statusCode = 200;
        await req.response.close();
      } else if (req.uri.path == "/tangent-webhook/ws") {
        req.headers.forEach((s, k) {
          print("$s: $k");
        });
        var ws = await WebSocketTransformer.upgrade(req);
        try {
          await for (var m in ws) {
            if (m is String) {
              var data = jsonDecode(m);
              if (data["secret"] == secret) {
                client = ws;
                if (queue.isNotEmpty) {
                  client.add(jsonEncode(queue));
                  queue.clear();
                }
              } else break;
            }
          }
          await ws.close();
        } finally {
          if (ws == client) client = null;
        }
      } else {
        req.response.statusCode = 500;
        await req.response.close();
      }
    });
  }, onError: (e, bt) {
    stderr.writeln(e);
    stderr.writeln(bt);
  });
}