import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:isolate' as iso;

import 'package:nyxx/Vm.dart';
import 'package:nyxx/nyxx.dart' as ds;
import 'package:path/path.dart' as path_util;
import 'dart:mirrors' as mirrors;
import 'package:vm_service_lib/vm_service_lib.dart' as vm;
import 'package:vm_service_lib/vm_service_lib_io.dart' as vm;
import 'dart:developer' as dev;
import 'package:yaml/yaml.dart';
import 'package:dartis/dartis.dart' as redis;

class TangentMsg {
  TangentMsg(this.id, this.m);
  ds.Snowflake id;
  ds.Message m;
  ds.MessageChannel get channel => m.channel;
  Future<ds.Message> reply(dynamic value) {
    var text = "$value";
    if (text.length > 1900) {
      text = text.substring(0, 1900) + "...";
    }

    if (m.channel is ds.TextChannel) {
      return m.channel.send(content: text);
    } else {
      return m.channel.send(content: text);
    }
  }
}

abstract class TangentModule {
  bool loaded = true;
  Future init() {}
  void onMessage(TangentMsg msg) {}
  void onMessageUpdate(TangentMsg oldMsg, TangentMsg newMsg) {}
  void onMessageDelete(TangentMsg msg) {}
  void onReady() {}
  Future unload() {}
}

ds.Nyxx nyxx;
redis.Client rclient;

Set<TangentModule> modules;

T getModule<T extends TangentModule>() {
  for (var m in modules) if (m is T) return m;
  return null;
}

String instanceName;
dynamic instanceData;

void main(List<String> args) async {
  if (args.isEmpty) throw "Instance name expected";
  instanceName = args.first;
  instanceData = loadYaml(await File("tokens/conf.yaml").readAsString())[args.first];

  await runZoned(() async {
    configureNyxxForVM();

    // Connect to Redis //

    if (instanceData["redis"] != null) {
      var rd = instanceData["redis"];
      var uri = Uri.parse(rd["uri"].toString());

      Socket sk;
      try {
        sk = await Socket.connect(uri.host, uri.port);
      } on SocketException catch (e) { // Server is down
        var rserver = await Process.start("redis-server", [
          "--daemonize", "yes",
          "--bind", "127.0.0.1",
          "--port", uri.port.toString(),
          "--protected-mode", "yes",
          "--appendonly", "yes",
          "--appendfsync", "everysec",
          "--save", "60", "1",
          "--dbfilename", "$instanceName.rdb",
          "--dir", "./db",
        ]);
        rserver.stdout.listen(stdout.add);
        rserver.stderr.listen(stderr.add);
        await Future.delayed(Duration(seconds: 2));
        sk = await Socket.connect(uri.host, uri.port);
      }

      rclient = await redis.Client(redis.Connection(sk));
    }

    // Connect to VM service //

    bool _sw(String s) {
      return Platform.executableArguments.any((ss) => ss.startsWith(s));
    }

    vm.VmService vmService;
    vm.VM vmMachine;
    vm.IsolateRef vmIsolate;
    dev.ServiceProtocolInfo vmInfo;

    if (_sw('--observe') || _sw('--enable-vm-service')) {
      vmInfo = await dev.Service.getInfo();
      var uri = vmInfo.serverUri;
      uri = uri.replace(path: path_util.join(uri.path, 'ws'));
      if (uri.scheme == 'https')
        uri = uri.replace(scheme: 'wss');
      else
        uri = uri.replace(scheme: 'ws');

      vmService = await vm.vmServiceConnectUri(uri.toString());
      vmMachine ??= await vmService.getVM();
      vmIsolate ??= vmMachine.isolates.first;

      for (var isolate in vmMachine.isolates) {
        await vmService.setExceptionPauseMode(isolate.id, 'None');
      }
    }

    print("Connected to VM service at ${vmInfo.serverUri}");

    print("Initializing...");

    modules = Set();

    Future unloadModules() async {
      for (var m in modules) {
        await m.unload();
        m.loaded = false;
      }
      modules.clear();
    }

    Future reloadModules() async {
      var tm = mirrors.reflectClass(TangentModule);
      for (var mn in (instanceData["modules"] as YamlList).map((d) => d.toString())) {
        var uri = Uri.parse("modules/$mn.dart");
        print("Loading module $uri");
        var lib = await mirrors.currentMirrorSystem().isolate.loadUri(uri);
        for (var decl in lib.declarations.values) {
          if (decl is mirrors.ClassMirror && decl.isSubclassOf(tm) && decl != tm) {
            modules.add(decl.newInstance(Symbol(""), []).reflectee);
          }
        }
      }

      for (var m in modules) {
        await m.init();
        print("Initialized ${m.runtimeType}");
      }

      if (nyxx?.ready == true) modules.forEach((m) => m.onReady());
    }

    LineSplitter().bind(Utf8Decoder().bind(stdin)).listen((line) async {
      var args = line.split(RegExp("\\s+"));
      var cmd = args.removeAt(0);
      if (cmd == "r") {
        print("Reloading...");
        await unloadModules();
        var report = await vmService.reloadSources(vmIsolate.id);
        if (!report.success) {
          stderr.writeln("Error during reload.");
          stderr.writeln("${report.toString()}");
        } else {
          print("Reload sucessful");
        }
        await reloadModules();
      }
    });

    await reloadModules();

    print("Connecting...");

    nyxx = ds.Nyxx(instanceData["token"], ignoreExceptions: false);

    nyxx.onReady.listen((ev) {
      modules.forEach((m) => m.onReady());
      print("Ready!");
    });

    nyxx.onMessageReceived.listen((ev) => modules.forEach((m) => m.onMessage(TangentMsg(ev.message.id, ev.message))));
    nyxx.onMessageUpdate.listen((ev) {
      if (ev.newMessage.author == null) return; // nyxx bug >.<
      modules.forEach((m) => m.onMessageUpdate(TangentMsg(ev.newMessage.id, ev.oldMessage), TangentMsg(ev.newMessage.id, ev.newMessage)));
    });
    nyxx.onMessageDelete.listen((ev) {
      modules.forEach((m) => m.onMessageDelete(TangentMsg(ev.id, ev.message)));
    });
  }, onError: (e, bt) {
    stderr.writeln("/// Zone Error ///");
    stderr.writeln(e);
    stderr.writeln(bt);
  });
}