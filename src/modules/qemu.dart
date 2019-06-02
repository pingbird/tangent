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

class QEmuModule extends TangentModule {
  Future<ProcessResult> runBasic(String command) => Process.run("/bin/bash", ["-c", command], stdoutEncoding: Utf8Codec(), stderrEncoding: Utf8Codec());

  Socket serviceSocket;
  var serviceConnect = Completer<Null>();
  Map<int, Completer<QProc>> starting;
  Map<int, QProc> procs;

  Future<QProc> startProc(String proc, List<String> args, {String workingDirectory, Map<String, String> environment, Future killOn}) async {
    if (serviceSocket == null) return null;
    var n = Random().nextInt(0x1000);
    while (starting.containsKey(n)) n++;
    serviceSocket.writeln(jsonEncode(["start", n, proc, args, workingDirectory, environment]));
    var c = Completer<QProc>();
    starting[n] = c;
    var p = await c.future;
    if (p == null) return null;

    unawaited(killOn?.then((_) => p.kill()));

    return p;
  }

  void procService() async {
    int lastConnect;
    int throttle = 0;
    while (loaded) {
      serviceSocket = null;
      procs = {};
      starting = {};
      Socket s;
      lastConnect = DateTime.now().millisecondsSinceEpoch;
      try {
        s = await Socket.connect("192.168.69.180", 5555, timeout: Duration(milliseconds: 500));
        print("[qemu] Connected to tangent-server");
        throttle = 0;
        serviceSocket = s;
        serviceConnect.complete();
        serviceConnect = Completer<Null>();
        await for (var line in s.transform(Utf8Decoder()).transform(
            LimitedLineSplitter(0x10000))) {
          print(line);
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
            var p = procs[cmd[1]];
            scheduleMicrotask(() async {
              unawaited(p.drain());
              await p.stdoutCtrl.close();
              await p.stderrCtrl.close();
              starting.remove(cmd[1]);
              procs.remove(cmd[1]);
              p.exitCodeCtrl.complete(cmd[2]);
            });
          } else if (cmd[0] == "err") {
            await Future.error(cmd[1], StackTrace.fromString(cmd[2]));
          }
        }
      } on SocketException catch (e) {
        //
      } catch (e, bt) {
        print("[qemu] Error! $e\n$bt");
        serviceSocket = null;
        await s?.close();
        for (var st in starting.values) {
          if (!st.isCompleted) st.complete(null);
        }

        for (var p in procs.values) {
          p.exitCodeCtrl.complete(255);
          await p.stdoutCtrl.close();
          await p.stderrCtrl.close();
        }
      }
      await Future.delayed(Duration(milliseconds: throttle));
      throttle = min(5000, throttle + 100);
    }
  }

  @override init() async {
    var r = await runBasic("sudo virsh start tangent");
    print("[qemu] Starting tangent");
    print(r.stdout + r.stderr);

    procService();
  }

  @Command(trusted: true) qclean(CommandArgs args) async {
    args.res.writeln("Cleaning...");
    var r = await runBasic("sudo virsh snapshot-revert tangent clean");
    args.res.writeln(r.stdout + r.stderr);
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

  @Command(trusted: true) qexec(CommandArgs args) async {
    args.res.writeln("Starting process...");
    var proc = await startProc("/bin/sh", ["-c", args.argText], workingDirectory: "/home/kek", killOn: args.onCancel);
    args.res.set("");
    if (proc == null) {
      args.res.writeln("Failed to start process");
      return args.res.close();
    }

    args.res.writeln("[${proc?.pid}]");

    proc.stdout.listen(args.res.add);
    proc.stderr.listen(args.res.add);
    var ex = await proc.exitCode;
    args.res.writeln("\n/bin/sh finished with exit code $ex");
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
    var m = RegExp("(.+?)\w*```(.+)```(.+?)").firstMatch(code);
    if (m != null) {
      cargs = ArgParse(m.group(1), parseFlags: false).list;
      code = m.group(2);
      pargs = ArgParse(m.group(3), parseFlags: false).list;
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
      ares.writeln("gcc finished with exit code $ec");
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

    var s = ares.messageText;

    ares.writeln("Running...");

    StreamGroup.merge([p.stdout, p.stderr]).listen((data) {
      if (s != null) ares.set(s);
      s = null;
      ares.add(data);
    });

    var ex = await p.exitCode;
    if (ex != 0 || s != null) {
      if (s != null) ares.set(s);
      ares.writeln("\n$program finished with exit code $ex");
    };
    return true;
  }

  @Command(trusted: true) gcc(CommandArgs args) async {
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

  @Command(trusted: true, alias: ["g++"]) gxx(CommandArgs args) async {
    var prog = extractArgs(args.argText);
    if (!await basicWrite(args.res, "./tangent.c", prog.item2))
      return args.res.close();

    if (!await basicCompile(
        args.res,
        prog.item2,
        "/usr/bin/g++",
        ["-o", "tangent", "tangent.c"]..addAll(prog.item1)
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
      ["./tangent.lua"]..addAll(prog.item3),
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