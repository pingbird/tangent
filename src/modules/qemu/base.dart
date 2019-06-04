import 'dart:async';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:pedantic/pedantic.dart';
import 'package:async/async.dart';
import 'package:tuple/tuple.dart';
import 'package:nyxx/nyxx.dart' as ds;

import '../../main.dart';
import '../../common.dart';
import '../commands.dart';

class QProc extends BasicStringSink {
  QProc(this.module, this.id, this.pid);
  QCtrl module;
  int id;
  int pid;
  var stdoutCtrl = StreamController<List<int>>();
  Stream<List<int>> get pstdout => stdoutCtrl.stream;
  var stderrCtrl = StreamController<List<int>>();
  Stream<List<int>> get pstderr => stderrCtrl.stream;

  Future drain() async {
    if (!stdoutCtrl.hasListener) await pstdout.drain();
    if (!stderrCtrl.hasListener) await pstderr.drain();
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
    module.lastUpload = DateTime.now().millisecondsSinceEpoch;
  }

  var closedCtrl = Completer<Null>();
  Future close() async {
    if (module.serviceSocket == null || exitCodeCtrl.isCompleted) return null;
    module.serviceSocket.writeln(jsonEncode(["close", id]));
    return closedCtrl.future;
  }

  get done => exitCode;

  void addError(Object error, [StackTrace stackTrace]) {
    stderr.writeln(error);
    stderr.writeln(stackTrace);
    close();
  }

  Future flush() => module.serviceSocket.flush();
}

Stream<T> dbgStream<T>(Stream<T> stream, String label) => stream.transform(
    StreamTransformer.fromHandlers(
      handleDone: (sink) {
        print("[dbStream] '$label' Done!");
        sink.close();
      },
      handleError: (e, bt, sink) {
        print("[dbStream] '$label' Error!");
        sink.addError(e, bt);
      },
    )
);

class QFile extends BasicStringSink {
  QFile(this.module, this.id);
  QCtrl module;
  int id;

  var opened = Completer<Null>();
  var closed = Completer<Null>();

  void add(List<int> event) {
    if (closed.isCompleted) return;
    module.serviceSocket.writeln(jsonEncode(["fwrite", id, Base64Codec().encode(event)]));
  }

  Future flush() => module.serviceSocket.flush();

  close() async {
    if (!opened.isCompleted) return null;
    if (closed.isCompleted) return null;
    closed.complete();
    if (module.serviceSocket == null) return null;
    module.serviceSocket.writeln(jsonEncode(["fclose", id]));
    return null;
  }

  bool destroyed = false;

  void destroy() {
    if (destroyed) return;
    destroyed = true;

    close();
    module.files.remove(id);

    if (!opened.isCompleted) opened.completeError("Failed to open file: Handle destroyed");

    if (sizeCtrl != null && !sizeCtrl.isCompleted) {
      sizeCtrl.completeError("Failed to get size: Handle destroyed");
    }

    if (readCtrl != null && !readCtrl.isClosed) {
      readCtrl.addError("Failed to read file: Handle destroyed");
    }
  }

  Future get done => closed.future;

  void addError(Object error, [StackTrace stackTrace]) {
    close();
    stderr.writeln(error);
    stderr.writeln(stackTrace);
  }

  Completer<int> sizeCtrl;
  Future<int> getSize() async {
    if (sizeCtrl == null) {
      module.serviceSocket.writeln(jsonEncode(["fsize", id]));
      sizeCtrl = Completer();
    }

    var s = await sizeCtrl.future;
    sizeCtrl = null;
    return s;
  }

  StreamController<List<int>> readCtrl;
  int readCtrlAmount;

  void readCtrlReq() {
    if (readCtrl.isClosed || readCtrl.isPaused || readCtrlAmount == 0) return;
    var n = min(0xA000, readCtrlAmount);
    readCtrlAmount -= n;
    module.serviceSocket.writeln(jsonEncode(["fread", id, n]));
  }

  void readCtrlAdd(List<int> d) {
    readCtrl.add(d);
    if (readCtrlAmount == 0) {
      readCtrl.close();
      destroy();
    }
    readCtrlReq();
  }

  Stream<List<int>> read(int bytes) {
    readCtrlAmount = bytes;
    readCtrl = StreamController(
      onListen: () {
        readCtrlReq();
      },
      onResume: () {
        readCtrlReq();
      },
    );
    return readCtrl.stream;
  }
}

class QCtrl {
  Future<ProcessResult> runBasic(String command) => Process.run("/bin/bash", ["-c", command], stdoutEncoding: Utf8Codec(), stderrEncoding: Utf8Codec());

  Socket serviceSocket;
  var serviceConnect = Completer<Null>();
  Map<int, Completer<QProc>> starting;
  Map<int, QProc> procs;
  Map<int, QFile> files;
  int lastUpload;

  Future<QProc> startProc(String proc, List<String> args, {String workingDirectory, Map<String, String> environment, Future killOn, bool drain = false}) async {
    if (serviceSocket == null) throw "Failed to start $proc: Server offline";
    var n = Random().nextInt(0x1000);
    while (starting.containsKey(n)) n++;
    serviceSocket.writeln(jsonEncode(["start", n, proc, args, workingDirectory, environment, drain]));
    var c = Completer<QProc>();
    starting[n] = c;
    var p = await c.future;

    unawaited(killOn?.then((_) => p.kill()));

    return p;
  }

  Future<QFile> openFile(String path, FileMode mode, {Future destroyOn}) async {
    if (serviceSocket == null) throw "Failed to open '$path': Server offline";

    var n = Random().nextInt(0x1000);
    while (files.containsKey(n)) n++;

    const modes = {
      FileMode.read: 0,
      FileMode.write: 1,
      FileMode.append: 2,
    };

    serviceSocket.writeln(jsonEncode(["fopen", n, path, modes[mode]]));
    var f = QFile(this, n);
    files[n] = f;

    unawaited(destroyOn.then((_) => f.destroy()));

    await f.opened.future;
    return f;
  }

  int lastConnectAttempt;
  int lastConnect;
  int pings;
  String connectionStateDbg;
  bool loaded;

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
      lastUpload = 0;
      lastConnectAttempt = DateTime.now().millisecondsSinceEpoch;

      try {
        connectionStateDbg = "connect";
        s = await Socket.connect("192.168.69.69", 5555, timeout: Duration(milliseconds: 500));
        print("[qemu] Connected to tangent-server");
        throttle = 0;
        connectionStateDbg = "connected";

        p = Timer.periodic(Duration(seconds: 5), (_) {
          try {
            if (pings == 0) {
              s.writeln(jsonEncode(["ping"]));
            }

            if (++pings >= 5 && DateTime.now().millisecondsSinceEpoch - lastUpload > 20000) {
              print("[qemu] Ping timeout, closing");
              s.close();
              s.destroy();
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
            var p = procs[cmd[1]];

            if (p == null) {
              starting[cmd[1]].completeError(cmd[2], StackTrace.fromString(cmd[3]));
            }

            connectionStateDbg = "exit";
            if (p != null) scheduleMicrotask(() async {
              unawaited(p.drain());
              await p.stdoutCtrl.close();
              await p.stderrCtrl.close();
              starting.remove(cmd[1]);
              procs.remove(cmd[1]);
              p.exitCodeCtrl.complete(cmd[2]);
            });
            connectionStateDbg = "connected";
          } else if (cmd[0] == "err") {
            connectionStateDbg = "err";
            await Future.error(cmd[1], StackTrace.fromString(cmd[2]));
            connectionStateDbg = "connected";
          } else if (cmd[0] == "pong") {
            pings = 0;
          } else if (cmd[0] == "fopened") {
            files[cmd[1]].opened.complete();
          } else if (cmd[0] == "ferror") {
            if (files[cmd[1]].opened.isCompleted) {
              files[cmd[1]].addError(cmd[2], StackTrace.fromString(cmd[3]));
            } else {
              files[cmd[1]].opened.completeError(cmd[2], StackTrace.fromString(cmd[3]));
            }

            unawaited(files[cmd[1]].close());
            files.remove(cmd[1]);
          } else if (cmd[0] == "fsize") {
            var c = files[cmd[1]].sizeCtrl;
            if (c != null && !c.isCompleted) {
              c.complete(cmd[2]);
            }
          } else if (cmd[0] == "fdata") {
            files[cmd[1]].readCtrlAdd(Base64Codec().decode(cmd[2]));
          }
        }

        lastConnect = DateTime.now().millisecondsSinceEpoch;
      } on SocketException catch (e) {
        print("[qemu] Error! $e");
        //
      } catch (e, bt) {
        connectionStateDbg = "qemuError";
        print("[qemu] Error! $e\n$bt");

        if (s != null) lastConnect = DateTime.now().millisecondsSinceEpoch;

        serviceSocket = null;
        await s?.close();
        s.destroy();
      }

      for (var st in starting.values) {
        if (!st.isCompleted) st.completeError("Failed to start process: Server disconnected");
      }

      for (var p in procs.values) {
        connectionStateDbg = "closing from error";
        unawaited(p.drain());
        await p.stdoutCtrl.close();
        await p.stderrCtrl.close();
        p.exitCodeCtrl.complete(255);
      }

      for (var f in files.values) f.destroy();

      connectionStateDbg = "throttle";
      p?.cancel();
      await Future.delayed(Duration(milliseconds: throttle));
      throttle = min(5000, throttle + 100);
    }

    connectionStateDbg = "unloaded";
  }

  Future<bool> basicRunProgram(CommandRes ares, String program, List<String> args) async {
    var t0 = DateTime.now().millisecondsSinceEpoch;

    var p = await startProc(program, args, killOn: ares.cancelled.future);
    if (p == null) {
      ares.writeln("Failed to run $program");
      return false;
    }

    var pre = ares.messageText;
    ares.writeln("Running...");
    StreamGroup.merge([p.pstdout, p.pstderr]).listen((data) {
      if (pre != null) ares.set(pre);
      pre = null;
      ares.add(data);
    });

    var ex = await p.exitCode;
    if (ex != 0 || pre != null) {
      if (pre != null) ares.set(pre);
      ares.writeln("\n$program finished with exit code $ex");
    };

    var t1 = DateTime.now().millisecondsSinceEpoch;
    print("[qemu] basicRunProgram $program : ${t1 - t0}ms");

    return true;
  }
}

abstract class _Task {}

class _SaveTask extends _Task {
  String path;
}

class _CompileTask extends _Task {
  String program;
  List<String> args;
  bool addArgs;
}

class _RunTask extends _Task {
  String program;
  List<String> args;
  bool addArgs;
}

class TaskBuilder {
  TaskBuilder(this.q, CommandArgs args) {
    code = args.argText;
    res = args.res;

    var m = RegExp(r"^([\S\s]+?)?```\w*([\S\s]+)```([\S\s]+)?$", multiLine: true).firstMatch(code);
    if (m != null) {
      cargs = ArgParse(m.group(1) ?? "", parseFlags: false).list;
      code = m.group(2);
      pargs = ArgParse(m.group(3) ?? "", parseFlags: false).list;
    }
  }

  QCtrl q;
  CommandRes res;
  String code;
  var cargs = <String>[];
  var pargs = <String>[];
  List<_Task> _tasks = [];

  TaskBuilder save(String path) {
    _tasks.add(_SaveTask()..path = path);
    return this;
  }

  TaskBuilder compile(String program, [List<String> args = const [], bool useCompArgs = true, bool addCode = false]) {
    args = args.toList();
    if (useCompArgs) args.addAll(cargs);
    if (addCode) args.add(code);
    _tasks.add(_CompileTask()
      ..program = program
      ..args = args
    );
    return this;
  }

  TaskBuilder run(String program, [List<String> args = const [], bool useProgArgs = true, bool addCode = false]) {
    args = args.toList();
    if (useProgArgs) args.addAll(pargs);
    if (addCode) args.add(code);
    _tasks.add(_RunTask()
      ..program = program
      ..args = args
    );
    return this;
  }

  Future done() async {
    var s = res.messageText;
    for (var task in _tasks) {
      var t0 = DateTime.now().millisecondsSinceEpoch;
      if (task is _SaveTask) {
        var f = await q.openFile(task.path, FileMode.write, destroyOn: res.cancelled.future);
        f.write(code);
        f.destroy();

        var t1 = DateTime.now().millisecondsSinceEpoch;
        print("[qemu] SaveTask ${task.path} : ${t1 - t0}ms");
      } else if (task is _CompileTask) {
        res.set("${s}Compiling...");
        var p = await q.startProc(task.program, task.args, killOn: res.cancelled.future);
        res.set(s);

        var cres = await StreamGroup.merge([p.pstdout, p.pstderr]).transform(Utf8Decoder()).join();

        var ec = await p.exitCode;
        if (ec != 0) {
          res.writeln("```$cres```");
          res.writeln("${task.program} finished with exit code $ec");
          break;
        }

        var t1 = DateTime.now().millisecondsSinceEpoch;
        print("[qemu] CompileTask ${task.program} : ${t1 - t0}ms");
      } else if (task is _RunTask) {
        var p = await q.startProc(task.program, task.args, killOn: res.cancelled.future);
        if (p == null) {
          res.writeln("Failed to run ${task.program}");
          return false;
        }

        var pre = res.messageText;
        res.writeln("Running...");
        StreamGroup.merge([p.pstdout, p.pstderr]).listen((data) {
          if (pre != null) res.set(pre);
          pre = null;
          res.add(data);
        });

        var ex = await p.exitCode;
        if (ex != 0 || pre != null) {
          if (pre != null) res.set(pre);
          res.writeln("\n${task.program} finished with exit code $ex");
        };

        var t1 = DateTime.now().millisecondsSinceEpoch;
        print("[qemu] basicRunProgram ${task.program} : ${t1 - t0}ms");
      }
    }

    return res.close();
  }
}