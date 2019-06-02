#!/usr/bin/dart

import 'dart:async';
import 'dart:io';
import 'dart:convert';

main() async {
  var server = await ServerSocket.bind("0.0.0.0", 5555);
  server.listen((cl) async {
    var p = <int, Process>{};
    void cleanup() {
      for (var proc in p.values) proc.kill(ProcessSignal.sigkill);
    }

    await runZoned(() async {
      void send(x) => cl.writeln(jsonEncode(x));

      try {
        await for (var line in cl.transform(Utf8Decoder()).transform(LineSplitter())) {
          print(line);
          var cmd = jsonDecode(line);
          if (cmd[0] == "start") {
            int id = cmd[1];
            p[id] = await Process.start(cmd[2], (cmd[3] as List)?.cast<String>(), workingDirectory: cmd[4], environment: (cmd[5] as Map)?.cast<String, String>());
            send(["started", id, p[id].pid]);

            bool stdoutDone = false;
            bool stderrDone = false;
            int exitCode;

            p[id].stdout.listen((data) {
              stdout.add(data);
              send(["stdout", id, Base64Codec().encode(data)]);
            }, onDone: () {
              stdoutDone = true;
              if (stderrDone && exitCode != null) {
                send(["exit", id, exitCode]);
                p.remove(id);
              }
            }, onError: (e) {
              stderr.writeln(e);
              cleanup();
            });

            p[id].stderr.listen((data) {
              stderr.add(data);
              send(["stderr", id, Base64Codec().encode(data)]);
            }, onDone: () {
              stderrDone = true;
              if (stdoutDone && exitCode != null) {
                send(["exit", id, exitCode]);
                p.remove(id);
              }
            }, onError: (e) {
              stderr.writeln(e);
              cleanup();
            });

            p[id].exitCode.then((e) {
              print("got exit code");
              exitCode = e;
              if (stdoutDone && stderrDone) {
                send(["exit", id, exitCode]);
                p.remove(id);
              }
            }, onError: (e) {
              stderr.writeln(e);
              cleanup();
            });
          } else if (cmd[0] == "stdin") {
            p[cmd[1]].stdin.add(Base64Codec().decode(cmd[2]));
          } else if (cmd[0] == "close") {
            await p[cmd[1]].stdin.close();
            send(["closed", cmd[1]]);
          } else if (cmd[0] == "kill") {
            print("killing");
            await Process.run("pkill", ["-P", "${p[cmd[1]].pid}"]);
            //p[cmd[1]].kill(ProcessSignal.sigkill);
          } else if (cmd[0] == "ping") {
            send(["pong"]);
          }
        }
      } catch (e, bt) {
        send(["err", e.toString(), bt.toString()]);
        cl.close();
      }
      cleanup();
    }, onError: (e, bt) {
      stderr.writeln(e);
      stderr.writeln(bt);
      cleanup();
    });
  });
}