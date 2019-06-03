import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:pedantic/pedantic.dart';
import 'package:async/async.dart';
import 'package:tuple/tuple.dart';
import 'package:nyxx/nyxx.dart' as ds;

import '../main.dart';
import '../common.dart';
import 'commands.dart';
import 'qemu/base.dart';

class QEmuModule extends TangentModule {
  QCtrl q;

  @override init() async {
    q = QCtrl();
    q.loaded = true;
    var r = await q.runBasic("sudo virsh start tangent");
    print("[qemu] Starting tangent");
    print(r.stdout + r.stderr);

    q.procService();
  }

  @override unload() async {
    q.loaded = false;
  }

  @Command(trusted: true) qdebug(CommandArgs args) async {
    args.res.writeln("[${q.connectionStateDbg}]");
    return args.res.close();
  }

  @Command(trusted: true) qclean(CommandArgs args) async {
    args.res.writeln("Cleaning...");
    var r = await q.runBasic("sudo virsh snapshot-revert tangent clean");
    args.res.writeln(((r.stdout as String) + r.stderr).trim());
    args.res.writeln("Done!");
    return args.res.close();
  }

  @Command(trusted: true) qstart(CommandArgs args) async {
    args.res.writeln("Starting...");
    var r = await q.runBasic("sudo virsh start tangent");
    args.res.writeln(((r.stdout as String) + r.stderr).trim());
    if (r.exitCode != 0) {
      args.res.writeln("virsh finished with exit code ${r.exitCode}");
      return args.res.close();
    }

    if (q.serviceSocket != null) {
      await q.serviceSocket?.close();
      q.serviceSocket = null;
    }

    args.res.writeln("Started, waiting for server to come online...");
    await q.serviceConnect.future;
    args.res.writeln("Done!");

    return args.res.close();
  }

  @Command(trusted: true) qrestart(CommandArgs args) async {
    args.res.writeln("Restarting...");
    var r = await q.runBasic("sudo virsh reboot tangent");
    args.res.writeln(((r.stdout as String) + r.stderr).trim());
    if (r.exitCode != 0) {
      args.res.writeln("virsh finished with exit code ${r.exitCode}");
      return args.res.close();
    }

    if (q.serviceSocket != null) {
      await q.serviceSocket?.close();
      q.serviceSocket = null;
    }

    args.res.writeln("Restarted, waiting for server to come back...");
    await q.serviceConnect.future;
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

    var file = await q.openFile(target, FileMode.write, destroyOn: args.onCancel);

    args.res.writeln("Downloading from Discord...");

    await Future.delayed(Duration(seconds: 1));

    print("[qemu] wget ${a.url}");

    var p = await Process.start("/usr/bin/wget", ["-qO-", a.url]);

    p.stderr.listen(stderr.add);

    args.res.writeln("Writing file to '$target'");

    int bytes = 0;

    int startTu = DateTime.now().millisecondsSinceEpoch;
    int lastTu = DateTime.now().millisecondsSinceEpoch;
    int lastBts = 0;
    var s = args.res.messageText;

    StreamSubscription<List<int>> sub;
    sub = p.stdout.listen((d) {
      bytes += d.length;
      lastBts += d.length;

      var t = DateTime.now().millisecondsSinceEpoch;
      if (t - lastTu > 1000) {
        args.res.set(s);
        args.res.writeln("`[${(100 * bytes / a.size).round()}% - ${sizeToString((1000 * lastBts / (t - lastTu)).round())}/s]`");
        lastTu = t;
        lastBts = 0;
      }

      file.add(d);
      sub.pause(file.flush());
    });

    unawaited(args.onCancel.then((_) => sub.cancel()));

    await sub.asFuture();
    await file.close();

    args.res.set(s);
    var t = DateTime.now().millisecondsSinceEpoch;
    args.res.writeln("`[Done! ${sizeToString((1000 * bytes / (t - startTu)).round())}/s]`");
    return args.res.close();
  }

  @Command(trusted: true) download(CommandArgs args) async {
    var ap = ArgParse(args.argText, parseFlags: false);

    if (ap.list.isEmpty) {
      args.res.writeln("Error: file name expected");
      return args.res.close();
    } else if (ap.list.length > 1) {
      args.res.writeln("Error: one argument expected (got ${ap.list.length}");
      return args.res.close();
    }

    var target = ap.list.first;
    var fn = Uri.parse(target).pathSegments.last;

    var file = await q.openFile(target, FileMode.read, destroyOn: args.onCancel);

    args.res.writeln("Downloading file...");

    List<int> bytes = [];
    var size = await file.getSize();

    args.res.writeln("Size: ${sizeToString(size)}");

    if (size > 8000000) {
      args.res.writeln("Error: file too large");
      return args.res.close();
    } else if (size == 0) {
      args.res.writeln("Error: file empty");
    }

    int startTu = DateTime.now().millisecondsSinceEpoch;
    int lastTu = DateTime.now().millisecondsSinceEpoch;
    int lastBts = 0;
    var s = args.res.messageText;

    await file.read(size).listen((d) {
      lastBts += d.length;

      var t = DateTime.now().millisecondsSinceEpoch;
      if (t - lastTu > 1000) {
        args.res.set(s);
        args.res.writeln("`[${(100 * bytes.length / size).round()}% - ${sizeToString((1000 * lastBts / (t - lastTu)).round())}/s]`");
        lastTu = t;
        lastBts = 0;
      }

      bytes.addAll(d);
    }).asFuture();

    args.res.set(s);
    var t = DateTime.now().millisecondsSinceEpoch;
    args.res.writeln("`[Done! ${sizeToString((1000 * size / (t - startTu)).round())}/s]`");

    args.res.writeln("Uploading to Discord...");

    await args.res.invokeMsg.channel.send(files: [
      ds.AttachmentBuilder.bytes(bytes, fn),
    ]);

    return args.res.close();
  }

  @Command(trusted: true) sh(CommandArgs args) async {
    await basicRunProgram(args.res, "/bin/sh", ["-c", args.argText]);
    return args.res.close();
  }

  @Command(trusted: true) bash(CommandArgs args) async {
    await basicRunProgram(args.res, "/bin/bash", ["-c", args.argText]);
    return args.res.close();
  }

  Future<bool> basicRunProgram(CommandRes ares, String program, List<String> args) async {
    var p = await q.startProc(program, args, killOn: ares.cancelled.future);
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
    return true;
  }

  @Command(trusted: true, alias: ["asm", "x86"]) x86(CommandArgs args) async {
    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./tangent.S", prog.item2))
      return args.res.close();

    if (!await q.basicCompile(
        args.res,
        "/usr/bin/gcc",
        ["-o", "tangent", "-masm=intel", "tangent.S"]..addAll(prog.item1)
    )) return args.res.close();

    if (!await basicRunProgram(args.res, "./tangent", prog.item3))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true) arm(CommandArgs args) async {
    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./tangent.S", prog.item2))
      return args.res.close();

    if (!await q.basicCompile(
        args.res,
        "/usr/bin/arm-linux-gnueabi-gcc",
        ["-o", "tangent", "-masm=intel", "tangent.S"]..addAll(prog.item1)
    )) return args.res.close();

    if (!await basicRunProgram(args.res, "./tangent", prog.item3))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["c", "gcc"]) gcc(CommandArgs args) async {
    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./tangent.c", prog.item2))
      return args.res.close();

    if (!await q.basicCompile(
        args.res,
        "/usr/bin/gcc",
        ["-o", "tangent", "tangent.c"]..addAll(prog.item1)
    )) return args.res.close();

    if (!await basicRunProgram(args.res, "./tangent", prog.item3))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["c++", "cpp", "g++"]) cpp(CommandArgs args) async {
    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./tangent.cpp", prog.item2))
      return args.res.close();

    if (!await q.basicCompile(
        args.res,
        "/usr/bin/g++",
        ["-o", "tangent", "tangent.cpp"]..addAll(prog.item1)
    )) return args.res.close();

    if (!await basicRunProgram(args.res, "./tangent", prog.item3))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["c-arm", "gcc-arm"]) gcc_arm(CommandArgs args) async {
    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./tangent.c", prog.item2))
      return args.res.close();

    if (!await q.basicCompile(
        args.res,
        "/usr/bin/arm-linux-gnueabi-gcc",
        ["-o", "tangent", "tangent.c"]..addAll(prog.item1)
    )) return args.res.close();

    if (!await basicRunProgram(args.res, "./tangent", prog.item3))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["c++-arm", "cpp-arm", "g++-arm"]) cpp_arm(CommandArgs args) async {
    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./tangent.cpp", prog.item2))
      return args.res.close();

    if (!await q.basicCompile(
        args.res,
        "/usr/bin/arm-linux-gnueabi-g++",
        ["-o", "tangent", "tangent.cpp"]..addAll(prog.item1)
    )) return args.res.close();

    if (!await basicRunProgram(args.res, "./tangent", prog.item3))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["lua", "lua53", "lua5.3"]) lua(CommandArgs args) async {
    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./tangent.lua", prog.item2))
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
    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./tangent.lua", prog.item2))
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
    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./tangent.lua", prog.item2))
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
    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./tangent.lua", prog.item2))
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
    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./tangent.py", prog.item2))
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
    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./tangent.py", prog.item2))
      return args.res.close();

    if (!await basicRunProgram(
      args.res,
      "/usr/bin/python2",
      ["./tangent.py"]..addAll(prog.item3),
    ))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["js", "node"]) js(CommandArgs args) async {
    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./tangent.js", prog.item2))
      return args.res.close();

    if (!await basicRunProgram(
      args.res,
      "/usr/bin/js",
      ["./tangent.js"]..addAll(prog.item3),
    ))
      return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["perl", "pl"]) perl(CommandArgs args) async {
    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./tangent.pl", prog.item2))
      return args.res.close();

    if (!await basicRunProgram(
      args.res,
      "/usr/bin/perl",
      ["./tangent.pl"]..addAll(prog.item3),
    )) return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["java", "jaba", "durga"]) java(CommandArgs args) async {
    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./Tangent.java", prog.item2))
      return args.res.close();

    if (!await q.basicCompile(
        args.res,
        "/usr/bin/javac",
        ["-g", "Tangent.java"]..addAll(prog.item1)
    )) return args.res.close();

    if (!await basicRunProgram(
        args.res,
        "/usr/bin/java",
        ["-cp", ".", "Tangent"]..addAll(prog.item3)
    )) return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["lisp", "sbcl"]) lisp(CommandArgs args) async {
    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./tangent.lisp", prog.item2))
      return args.res.close();

    if (!await basicRunProgram(
      args.res,
      "/usr/bin/sbcl",
      ["./tangent.lisp"]..addAll(prog.item3),
    )) return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["bf", "brainfuck"]) bf(CommandArgs args) async {
    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./tangent.bf", prog.item2))
      return args.res.close();

    if (!await basicRunProgram(
      args.res,
      "/usr/bin/sh",
      ["-c", "cat ./tangent.bf | hsbrainfuck"],
    )) return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["c#", "cs", "csharp"]) csharp(CommandArgs args) async {
    if (!await q.basicCompile(
      args.res,
      "/usr/bin/dotnet",
      ["new", "console", "--force"]
    )) return args.res.close();

    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./Program.cs", prog.item2))
      return args.res.close();

    if (!await basicRunProgram(
      args.res,
      "/usr/bin/dotnet",
      ["run", "-p=kek.csproj"],
    )) return args.res.close();

    return args.res.close();
  }

  @Command(trusted: true, alias: ["f#", "fs", "fsharp"]) fsharp(CommandArgs args) async {
    if (!await q.basicCompile(
      args.res,
      "/usr/bin/dotnet",
      ["new", "console", "--force", "--language=f#"]
    )) return args.res.close();

    var prog = q.extractArgs(args.argText);
    if (!await q.basicWrite(args.res, "./Program.fs", prog.item2))
      return args.res.close();

    if (!await basicRunProgram(
      args.res,
      "/usr/bin/dotnet",
      ["run", "-p=kek.fsproj"],
    )) return args.res.close();

    return args.res.close();
  }
}