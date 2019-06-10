import 'dart:io';

import 'package:tangent/base.dart';
import 'package:tangent/common.dart';
import 'package:tangent/modules/commands.dart';

class WebserverModule extends TangentModule {
  HttpServer server;
  Future init() async {
    server = HttpServer.listenOn(await ServerSocket.bind("127.0.0.1", 5959));
    server.listen((req) async {
      req.response.statusCode = 200;
      req.response.headers.set("Content-Type", "text/html");
      req.response.writeln("<h1>Hello :)</h1>");
      await req.response.close();
    });
  }

  Future unload() async {
    await server.close(force: true);
  }
}