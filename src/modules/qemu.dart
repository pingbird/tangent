import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:pedantic/pedantic.dart';
import 'package:async/async.dart';
import 'package:tuple/tuple.dart';

import '../main.dart';
import '../common.dart';
import 'commands.dart';

class QProc extends BasicStringSink {
  QProc(this.module, this.id, this.pid);
  QEmuModule module;
  int id;
  int pid;
  var stdoutCtrl = StreamController<List<int>>();
  Stream<List<int>> get stdout => stdoutCtrl.stream;
  var stderrCtrl = StreamController<List<int>>();
  Stream<List<int>> get stderr => stderrCtrl.stream;

  Future drain() async {
    if (!stdoutCtrl.hasListener) await stdout.drain();
    if (!stderrCtrl.hasListener) await stderr.drain();
  }

  var exitCodeCtrl = Completer<int>();
  Future<int> get exitCode => exitCodeCtrl.future;

  void kill() {
    if (module.serviceSocket == null || exitCodeCtrl.isCompleted) return null;
    module.serviceSocket.writeln(jsonEncode(["kill", id]));
  }

  void add(List<int> data) {
    if (module.serviceSocket == null || exitCodeCtrl.isCompleted) return null;
    module.serviceSocket.writeln(jsonEncode(["stdin", id, Base64Codec().encode(data)]));
  }

  var closedCtrl = Completer<Null>();
  Future close() async {
    if (module.serviceSocket == null || exitCodeCtrl.isCompleted) return null;
    module.serviceSocket.writeln(jsonEncode(["close", id]));
    return closedCtrl.future;
  }

  get done => exitCode;
}

class QFile extends BasicStringSink {
  QFile(this.module, this.id);
  QEmuModule module;
  int id;

  var closed = Completer<Null>();

  void add(List<int> event) {
    if (closed.isCompleted) return;
    module.serviceSocket.writeln(jsonEncode(["fwrite", id, Base64Codec().encode(event)]));
  }

  Future close() async {
    if (closed.isCompleted) return null;
    closed.complete();
    if (module.serviceSocket == null) return null;
    module.serviceSocket.writeln(jsonEncode(["fclose", id]));
    return null;
  }

  Future get done => closed.future;
}

class QEmuModule extends TangentModule {
  Future<ProcessResult> runBasic(String command) => Process.run("/bin/bash", ["-c", command], stdoutEncoding: Utf8Codec(), stderrEncoding: Utf8Codec());

  Socket serviceSocket;
  var serviceConnect = Completer<Null>();
  Map<int, Completer<QProc>> starting;
  Map<int, QProc> procs;
  Map<int, QFile> files;

  Future<QProc> startProc(String proc, List<String> args, {String workingDirectory, Map<String, String> environment, Future killOn, bool drain = false}) async {
    if (serviceSocket == null) return null;
    var n = Random().nextInt(0x1000);
    while (starting.containsKey(n)) n++;
    serviceSocket.writeln(jsonEncode(["start", n, proc, args, workingDirectory, environment, drain]));
    var c = Completer<QProc>();
    starting[n] = c;
    var p = await c.future;
    if (p == null) return null;

    unawaited(killOn?.then((_) => p.kill()));

    return p;
  }

  Future<QFile> openFile(String path, {Future killOn}) async {
    if (serviceSocket == null) return null;

    var n = Random().nextInt(0x1000);
    while (files.containsKey(n)) n++;
    serviceSocket.writeln(jsonEncode(["fopen", n, path]));
    files[n] = QFile(this, n);
    return files[n];
  }

  int lastConnectAttempt;
  int lastConnect;
  int pings;
  String connectionStateDbg;

  void procService() async {
    int throttle = 0;
    while (loaded) {
      connectionStateDbg = "loop";
      if (lastConnect != null && DateTime.now().millisecondsSinceEpoch - lastConnect > 10000) {
        connectionStateDbg = "rebooting";
        print("[qemu] Attempting to reboot tangent");
        var r = await runBasic("sudo virsh reboot tangent");
        if (r.exitCode != 0) {
          stderr.writeln("[eqmu] Failed to reboot tangent!");
          await Future.delayed(Duration(seconds: 10));
        }
        lastConnect = DateTime.now().millisecondsSinceEpoch;
      }

      serviceSocket = null;
      procs = {};
      starting = {};
      files = {};
      Socket s;
      Timer p;
      pings = 0;
      lastConnectAttempt = DateTime.now().millisecondsSinceEpoch;
      try {
        connectionStateDbg = "connect";
        s = await Socket.connect("192.168.69.180", 5555, timeout: Duration(milliseconds: 500));
        print("[qemu] Connected to tangent-server");
        throttle = 0;
        connectionStateDbg = "connected";

        p = Timer.periodic(Duration(seconds: 1), (_) {
          try {
            if (pings == 0) {
              s.writeln(jsonEncode(["ping"]));
            }

            if (++pings >= 5) {
              print("[qemu] Ping timeout, closing");
              s.close();
              p?.cancel();
            }
          } catch (e) {
            p?.cancel();
          }
        });

        serviceSocket = s;
        serviceConnect.complete();
        serviceConnect = Completer<Null>();
        await for (var line in s.transform(Utf8Decoder()).transform(LimitedLineSplitter(0x10000))) {
          var cmd = jsonDecode(line);
          if (cmd[0] == "started") {
            var p = QProc(this, cmd[1], cmd[2]);
            starting[cmd[1]].complete(p);
            procs[cmd[1]] = p;
          } else if (cmd[0] == "stdout") {
            procs[cmd[1]].stdoutCtrl.add(Base64Codec().decode(cmd[2]));
          } else if (cmd[0] == "stderr") {
            procs[cmd[1]].stderrCtrl.add(Base64Codec().decode(cmd[2]));
          } else if (cmd[0] == "closed") {
            procs[cmd[1]].closedCtrl.complete();
          } else if (cmd[0] == "exit") {
            connectionStateDbg = "exit";
            var p = procs[cmd[1]];
            scheduleMicrotask(() async {
              unawaited(p.drain());
              await p.stdoutCtrl.close();
              await p.stderrCtrl.close();
              starting.remove(cmd[1]);
              procs.remove(cmd[1]);
              p.exitCodeCtrl.complete(cmd[2]);
            });
            connectionStateDbg = "loop";
          } else if (cmd[0] == "err") {
            connectionStateDbg = "err";
            await Future.error(cmd[1], StackTrace.fromString(cmd[2]));
            connectionStateDbg = "loop";
          } else if (cmd[0] == "pong") {
            pings = 0;
          }
        }

        lastConnect = DateTime.now().millisecondsSinceEpoch;
      } on SocketException catch (e) {
        //
      } catch (e, bt) {
        print("[qemu] Error! $e\n$bt");

        if (s != null) lastConnect = DateTime.now().millisecondsSinceEpoch;

        serviceSocket = null;
        await s?.close();
        for (var st in starting.values) {
          if (!st.isCompleted) st.complete(null);
        }

        for (var p in procs.values) {
          connectionStateDbg = "closing from error";
          unawaited(p.drain());
          await p.stdoutCtrl.close();
          await p.stderrCtrl.close();
          p.exitCodeCtrl.complete(255);
        }
      }

      connectionStateDbg = "throttle";
      p?.cancel();
      await Future.delayed(Duration(milliseconds: throttle));
      throttle = min(5000, throttle + 100);
    }

    connectionStateDbg = "unloaded";
  }

  @override init() async {
    var r = await runBasic("sudo virsh start tangent");
    print("[qemu] Starting tangent");
    print(r.stdout + r.stderr);

    procService();
  }

  @Command(trusted: true) qdebug(CommandArgs args) async {
    args.res.writeln("[${connectionStateDbg}]");
    return args.res.close();
  }

  @Command(trusted: true) qclean(CommandArgs args) async {
    args.res.writeln("Cleaning...");
    var r = await runBasic("sudo virsh snapshot-revert tangent clean");
    args.res.writeln(r.stdout + r.stderr);
    args.res.writeln("Done!");
    return args.res.close();
  }

  @Command(trusted: true) qstart(CommandArgs args) async {
    args.res.writeln("Starting...");
    var r = await runBasic("sudo virsh start tangent");
    args.res.writeln(((r.stdout as String) + r.stderr).trim());
    if (r.exitCode != 0) {
      args.res.writeln("virsh finished with exit code ${r.exitCode}");
      return args.res.close();
    }

    if (serviceSocket != null) {
      await serviceSocket?.close();
      serviceSocket = null;
    }

    args.res.writeln("Started, waiting for server to come online...");
    await serviceConnect.future;
    args.res.writeln("Done!");

    return args.res.close();
  }

  @Command(trusted: true) qrestart(CommandArgs args) async {
    args.res.writeln("Restarting...");
    var r = await runBasic("sudo virsh reboot tangent");
    args.res.writeln(((r.stdout as String) + r.stderr).trim());
    if (r.exitCode != 0) {
      args.res.writeln("virsh finished with exit code ${r.exitCode}");
      return args.res.close();
    }

    if (serviceSocket != null) {
      await serviceSocket?.close();
      serviceSocket = null;
    }

    args.res.writeln("Restarted, waiting for server to come back...");
    await serviceConnect.future;
    args.res.writeln("Done!");

    return args.res.close();
  }

  @Command(trusted: true) upload(CommandArgs args) async {
    var ap = ArgParse(args.argText, parseFlags: false);
    String target;

    if (ap.list.isEmpty) {
      target = "/home/kek/";
    } else {
      if (ap.list.length > 1) {
        args.res.writeln("Error: one argument expected (got ${ap.list.length}");
        return args.res.close();
      }
      target = ap.list.first;
    }

    bool toDir = target.endsWith("/");

    var attach = args.msg.m.attachments?.values;

    if (attach == null || attach.isEmpty) {
      args.res.writeln("Error: attachment expected");
      return args.res.close();
    } else if (attach.length > 1) {
      args.res.writeln("Error: one attachment expected");
      return args.res.close();
    }

    var a = attach.first;

    if (toDir) {
      target += a.filename;
    }

    var file = await openFile(target, killOn: args.onCancel);
    if (file == null) {
      args.res.writeln("Failed to open $target");
      return false;
    }

    await Future.delayed(Duration(seconds: 1));

    args.res.writeln("Downloading from discord...");

    var req = await HttpClient().getUrl(Uri.parse(a.url));
    req.headers.set("User-Agent", "Tangent bot");

    var resp = await req.close();

    args.res.writeln("Uploading to vm...");

    await file.addStream(resp);
    await file.close();

    args.res.writeln("Done!");
    args.res.writeln("wrote ${a.size} bytes to $target");
    return args.res.close();
  }

  @Command(trusted: true) sh(CommandArgs args) async {
    await basicRunProgram(args.res, "/bin/sh", ["-c", args.argText]);
    return args.res.close();
  }

  Future<bool> basicWrite(CommandRes ares, String file, String text) async {
    var p = await startProc("tee", [file], killOn: ares.cancelled.future);
    if (p == null) {
      ares.writeln("Failed to write file");
      return false;
    }
    p.write(text);
    await p.close();
    await p.exitCode;
    return true;
  }

  Tuple3<List<String>, String, List<String>> extractArgs(String code) {
    var cargs = <String>[];
    var pargs = <String>[];
    var m = RegExp(r"^([\S\s]+?)?```\w*([\S\s]+)```([\S\s]+)?$", multiLine: true).firstMatch(code);
    if (m != null) {
      cargs = ArgParse(m.group(1) ?? "", parseFlags: false).list;
      code = m.group(2);
      pargs = ArgParse(m.group(3) ?? "", parseFlags: false).list;
    }
    return Tuple3(cargs, code, pargs);
  }

  Future<bool> basicCompile(CommandRes ares, String code, String compiler, List<String> args) async {
    var s = ares.messageText;

    ares.set("${s}Compiling...");
    var p = await startProc(compiler, args, killOn: ares.cancelled.future);
    if (p == null) {
      ares.writeln("Failed to start ${compiler}");
      return false;
    }
    ares.set(s);

    var res = await StreamGroup.merge([p.stdout, p.stderr]).transform(Utf8Decoder()).join();

    var ec = await p.exitCode;
    if (ec != 0) {
      ares.writeln("```$res```");
      ares.writeln("$compiler finished with exit code $ec");
      return false;
    }

    return true;
  }

  Future<bool> basicRunProgram(CommandRes ares, String program, List<String> args) async {
    var p = await startProc(program, args, killOn: ares.cancelled.future);
    if (p == null) {
      ares.writeln("Failed to run $program");
      return false;
    }

    var pre = ares.messageText;
    ares.writeln("Running...");
    StreamGroup.merge([p.stdout, p.stderr]).listen((data) {
      if (pre != null) ares.set(pre);
      pre = null;
      ares.add(data);
    });

    var ex = await p.exitCode;
    if (ex != 0 || pre != null) {
      if (pre != null) ares.set(pre);
      ares.writeln("\n$program finished with exit code $ex");
    };
    return true;
  }

  @Command(trusted: true, alias: ["asm", "x86"]) x86(CommandArgs args) async {
    var prog = extractArgs(args.argText);
    if (!await basicWrite(args.res, "./tangent.S", prog.item2))
      return args.res.close();

    if (!await basicCompile(
        args.res,
        prog.item2,
        "/usr/bin/gcc",
        ["-o", "tangent", "-masm=intel", "tangent.S"]..addAll(prog.item1)
    )) return args.res.close();

    if (!await basicRunProgram(args.res, "./tangent", prog.item3))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true) arm(CommandArgs args) async {
    var prog = extractArgs(args.argText);
    if (!await basicWrite(args.res, "./tangent.S", prog.item2))
      return args.res.close();

    if (!await basicCompile(
        args.res,
        prog.item2,
        "/usr/bin/arm-linux-gnueabi-gcc",
        ["-o", "tangent", "-masm=intel", "tangent.S"]..addAll(prog.item1)
    )) return args.res.close();

    if (!await basicRunProgram(args.res, "./tangent", prog.item3))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["c", "gcc"]) gcc(CommandArgs args) async {
    var prog = extractArgs(args.argText);
    if (!await basicWrite(args.res, "./tangent.c", prog.item2))
      return args.res.close();

    if (!await basicCompile(
        args.res,
        prog.item2,
        "/usr/bin/gcc",
        ["-o", "tangent", "tangent.c"]..addAll(prog.item1)
    )) return args.res.close();

    if (!await basicRunProgram(args.res, "./tangent", prog.item3))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["c++", "cpp", "g++"]) cpp(CommandArgs args) async {
    var prog = extractArgs(args.argText);
    if (!await basicWrite(args.res, "./tangent.cpp", prog.item2))
      return args.res.close();

    if (!await basicCompile(
        args.res,
        prog.item2,
        "/usr/bin/g++",
        ["-o", "tangent", "tangent.cpp"]..addAll(prog.item1)
    )) return args.res.close();

    if (!await basicRunProgram(args.res, "./tangent", prog.item3))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["c-arm", "gcc-arm"]) gcc_arm(CommandArgs args) async {
    var prog = extractArgs(args.argText);
    if (!await basicWrite(args.res, "./tangent.c", prog.item2))
      return args.res.close();

    if (!await basicCompile(
        args.res,
        prog.item2,
        "/usr/bin/arm-linux-gnueabi-gcc",
        ["-o", "tangent", "tangent.c"]..addAll(prog.item1)
    )) return args.res.close();

    if (!await basicRunProgram(args.res, "./tangent", prog.item3))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["c++-arm", "cpp-arm", "g++-arm"]) cpp_arm(CommandArgs args) async {
    var prog = extractArgs(args.argText);
    if (!await basicWrite(args.res, "./tangent.cpp", prog.item2))
      return args.res.close();

    if (!await basicCompile(
        args.res,
        prog.item2,
        "/usr/bin/arm-linux-gnueabi-g++",
        ["-o", "tangent", "tangent.cpp"]..addAll(prog.item1)
    )) return args.res.close();

    if (!await basicRunProgram(args.res, "./tangent", prog.item3))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["lua", "lua53", "lua5.3"]) lua(CommandArgs args) async {
    var prog = extractArgs(args.argText);
    if (!await basicWrite(args.res, "./tangent.lua", prog.item2))
      return args.res.close();

    if (!await basicRunProgram(
      args.res,
      "/usr/bin/lua5.3",
      ["./tangent.lua"]..addAll(prog.item3),
    ))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["lua52", "lua5.2"]) lua52(CommandArgs args) async {
    var prog = extractArgs(args.argText);
    if (!await basicWrite(args.res, "./tangent.lua", prog.item2))
      return args.res.close();

    if (!await basicRunProgram(
      args.res,
      "/usr/bin/lua5.2",
      ["./tangent.lua"]..addAll(prog.item3),
    ))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["lua51", "lua5.1"]) lua51(CommandArgs args) async {
    var prog = extractArgs(args.argText);
    if (!await basicWrite(args.res, "./tangent.lua", prog.item2))
      return args.res.close();

    if (!await basicRunProgram(
      args.res,
      "/usr/bin/lua5.1",
      ["./tangent.lua"]..addAll(prog.item3),
    ))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true) luajit(CommandArgs args) async {
    var prog = extractArgs(args.argText);
    if (!await basicWrite(args.res, "./tangent.lua", prog.item2))
      return args.res.close();

    if (!await basicRunProgram(
      args.res,
      "/usr/bin/luajit",
      ["./tangent.lua"]..addAll(prog.item3),
    ))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["py", "py3", "python", "python3"]) py(CommandArgs args) async {
    var prog = extractArgs(args.argText);
    if (!await basicWrite(args.res, "./tangent.py", prog.item2))
      return args.res.close();

    if (!await basicRunProgram(
      args.res,
      "/usr/bin/python3",
      ["./tangent.py"]..addAll(prog.item3),
    ))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["py2", "python2"]) py2(CommandArgs args) async {
    var prog = extractArgs(args.argText);
    if (!await basicWrite(args.res, "./tangent.py", prog.item2))
      return args.res.close();

    if (!await basicRunProgram(
      args.res,
      "/usr/bin/python2",
      ["./tangent.py"]..addAll(prog.item3),
    ))
      return args.res.close();

    return args.res.close();
  }
}