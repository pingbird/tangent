import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

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
  var exitCodeCtrl = Completer<int>();
  Future<int> get exitCode => exitCodeCtrl.future;

  void kill() {
    if (module.serviceSocket == null) return;
    if (exitCodeCtrl.isCompleted) return;
    module.serviceSocket.writeln(jsonEncode({0: "kill", 1: id}));
  }

  void add(List<int> data) {
    if (module.serviceSocket == null) return;
    if (exitCodeCtrl.isCompleted) return;
    module.serviceSocket.writeln(jsonEncode(["stdin", id, Base64Codec().encode(data)]));
  }

  close() => null;
  get done => exitCode;
}

class QEmuModule extends TangentModule {
  Future<ProcessResult> runBasic(String command) => Process.run("/bin/bash", ["-c", command], stdoutEncoding: Utf8Codec(), stderrEncoding: Utf8Codec());

  Socket serviceSocket;
  Map<int, Completer<QProc>> starting;
  Map<int, QProc> procs;

  Future<QProc> startProc(String proc, List<String> args, {String workingDirectory, Map<String, String> environment}) async {
    if (serviceSocket == null) return null;
    var n = Random().nextInt(0x1000);
    while (starting.containsKey(n)) n++;
    serviceSocket.writeln(jsonEncode(["start", n, proc, args, workingDirectory, environment]));
    var c = Completer<QProc>();
    starting[n] = c;
    return c.future;
  }

  void procService() async {
    while (true) {
      serviceSocket = null;
      procs = {};
      starting = {};
      Socket s;
      try {
        s = await Socket.connect("192.168.69.180", 5555, timeout: Duration(milliseconds: 500));
        print("[qemu] Connected to tangent-client");
        serviceSocket = s;
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
          } else if (cmd[0] == "exit") {
            var p = procs[cmd[1]];
            p.exitCodeCtrl.complete(cmd[2]);
            await p.stdoutCtrl.close();
            await p.stderrCtrl.close();
            starting.remove(cmd[1]);
            procs.remove(cmd[1]);
          } else if (cmd[0] == "err") {
            await Future.error(cmd[1], StackTrace.fromString(cmd[2]));
          }
        }
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
      await Future.delayed(Duration(seconds: 5));
    }
  }

  @override init() async {
    var r = await runBasic("sudo virsh start tangent");
    print("[qemu] Starting tangent");
    print(r.stdout + r.stderr);

    procService();
  }

  @Command(trusted: true) qrestart(CommandArgs args) async {
    args.res.writeln("Restarting...");
    var r = await runBasic("sudo virsh reboot tangent");
    args.res.writeln(r.stdout + r.stderr);
    return args.res.close();
  }

  @Command(trusted: true) qclean(CommandArgs args) async {
    args.res.writeln("Cleaning...");
    var r = await runBasic("sudo virsh snapshot-revert tangent clean");
    args.res.writeln(r.stdout + r.stderr);
    args.res.writeln("Done!");
    return args.res.close();
  }

  @Command(trusted: true) qexec(CommandArgs args) async {
    var proc = await startProc("/bin/sh", ["-c", args.argText], workingDirectory: "/home/kek");
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
}