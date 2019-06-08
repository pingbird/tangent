import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:pedantic/pedantic.dart';
import 'package:async/async.dart';
import 'package:tuple/tuple.dart';
import 'package:nyxx/nyxx.dart' as ds;

import 'package:tangent/base.dart';
import 'package:tangent/common.dart';
import 'package:tangent/modules/commands.dart';
import 'controller.dart';

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

  @Command() upload(CommandArgs args) async {
    var ap = ArgParse(args.text, parseFlags: false);
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

  @Command() download(CommandArgs args) async {
    var ap = ArgParse(args.text, parseFlags: false);

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

  @Command()
  sh(CommandArgs args) => TaskBuilder(q, args)
    .run("/bin/sh", ["-c"], false, true).done();

  @Command()
  bash(CommandArgs args) => TaskBuilder(q, args)
    .run("/bin/bash", ["-c"], false, true).done();

  @Command(alias: ["asm", "x86"])
  x86(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.S")
    .compile("gcc", ["-static", "-o", "tangent", "tangent.S"])
    .run("./tangent").done();

  @Command()
  arm(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.S")
    .compile("arm-linux-gnueabi-gcc", ["-o", "tangent", "tangent.S"])
    .run("./tangent").done();

  @Command(alias: ["c", "gcc"])
  gcc(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.c")
    .compile("gcc", ["-o", "tangent", "tangent.c"])
    .run("./tangent").done();

  @Command(alias: ["c++", "cpp", "g++"])
  cpp(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.cpp")
    .compile("g++", ["-o", "tangent", "tangent.cpp"])
    .run("./tangent").done();

  @Command(alias: ["c-arm", "gcc-arm"])
  gcc_arm(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.c")
    .compile("arm-linux-gnueabi-gcc", ["-o", "tangent", "tangent.c"])
    .run("./tangent").done();

  @Command(alias: ["c++-arm", "cpp-arm", "g++-arm"])
  cpp_arm(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.cpp")
    .compile("arm-linux-gnueabi-g++", ["-o", "tangent", "tangent.cpp"])
    .run("./tangent").done();

  @Command(alias: ["lua", "lua53", "lua5.3"])
  lua(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.lua")
    .run("lua5.3", ["tangent.lua"]).done();

  @Command(alias: ["lua52", "lua5.2"])
  lua52(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.lua")
    .run("lua5.2", ["tangent.lua"]).done();

  @Command(alias: ["lua51", "lua5.1"])
  lua51(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.lua")
    .run("lua5.1", ["tangent.lua"]).done();

  @Command()
  luajit(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.lua")
    .run("luajit", ["tangent.lua"]).done();

  @Command(alias: ["py", "py3", "python", "python3"])
  py(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.py")
    .run("python3", ["tangent.py"]).done();

  @Command(alias: ["py2", "python2"])
  py2(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.py")
    .run("python2", ["tangent.py"]).done();

  @Command(alias: ["js", "node"])
  js(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.js")
    .run("js", ["-p"], false, true).done();

  @Command(alias: ["perl", "pl"])
  perl(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.pl")
    .run("perl", ["tangent.pl"]).done();

  @Command(alias: ["java", "jaba", "durga"])
  java(CommandArgs args) => TaskBuilder(q, args)
    .save("Tangent.java")
    .compile("/usr/bin/javac", ["Tangent.java"])
    .run("java", ["-cp", ".", "Tangent"]).done();

  @Command(alias: ["lisp", "sbcl"])
  lisp(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.lisp")
    .run("sbcl", ["--script", "./tangent.lisp"]).done();

  @Command(alias: ["bf", "brainfuck"])
  bf(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.bf")
    .run("sh", ["-c", "cat ./tangent.bf | hsbrainfuck"]).done();

  @Command(alias: ["c#", "cs", "csharp"])
  csharp(CommandArgs args) => TaskBuilder(q, args)
    .compile("dotnet", ["new", "console", "--force", "--no-restore"], false)
    .save("Program.cs")
    .compile("dotnet", ["restore", "kek.csproj", "-s", "/opt/Tangent/.nuget/packages"])
    .run("dotnet", ["run", "-p=kek.csproj"]).done();

  @Command(alias: ["f#", "fs", "fsharp"])
  fsharp(CommandArgs args) => TaskBuilder(q, args)
    .compile("dotnet", ["new", "console", "--force", "--language=f#", "--no-restore"])
    .save("Program.fs")
    .compile("dotnet", ["restore", "kek.fsproj", "-s", "/opt/Tangent/.nuget/packages"])
    .run("dotnet", ["run", "-p=kek.fsproj"]).done();

  @Command(alias: ["hs", "ghc", "haskell"])
  haskell(CommandArgs args) => TaskBuilder(q, args)
    .save("Tangent.hs")
    .compile("ghc", ["Tangent.hs"])
    .run("./Tangent").done();

  @Command()
  php(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.php")
    .run("php", ["tangent.php"]).done();

  @Command()
  cobol(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.cob")
    .compile("cobc", ["-free", "-x", "-o", "tangent", "tangent.cob"])
    .run("./tangent").done();

  @Command()
  go(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.go")
    .run("go", ["run", "tangent.go"]).done();

  @Command()
  ruby(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.rb")
    .run("ruby", ["tangent.rb"]).done();

  @Command()
  apl(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.apl")
    .run("apl", ["--script", "-f", "tangent.apl"]).done();

  @Command()
  prolog(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.pl")
    .run("swipl", ["-q", "-l", "tangent.pl"]).done();

  @Command()
  ocaml(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.ml")
    .run("ocaml", ["tangent.ml"]).done();

  @Command()
  sml(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.sml")
    .run("sh", ["-c", "sml < tangent.sml"]).done();

  @Command()
  crystal(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.cr")
    .run("crystal", ["tangent.cr"]).done();

  @Command()
  ada(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.adb")
    .compile("gcc", ["-c", "tangent.adb"])
    .compile("gnatbind", ["tangent"])
    .compile("gnatlink", ["tangent"])
    .run("./tangent").done();

  @Command()
  d(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.d")
    .compile("gdc", ["tangent.d", "-o", "tangent"])
    .run("./tangent").done();

  @Command()
  groovy(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.groovy")
    .run("groovy", ["tangent.groovy"]).done();

  @Command()
  dart(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.dart")
    .run("dart", ["tangent.dart"]).done();

  @Command()
  erlang(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.erl")
    .compile("erlc", ["tangent.erl"])
    .run("erl", ["-noshell", "-s", "tangent", "main", "-s", "init", "stop"]).done();

  @Command()
  forth(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.fth")
    .run("gforth", ["tangent.fth", "-e", "bye"]).done();

  @Command()
  pascal(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.p")
    .compile("fpc", ["tangent.p"])
    .run("./tangent").done();

  @Command()
  fortran(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.f")
    .compile("gfortran", ["-o", "tangent", "tangent.f"])
    .run("./tangent").done();

  @Command()
  hack(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.hack")
    .run("hhvm", ["tangent.hack"]).done();

  @Command()
  julia(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.jl")
    .run("julia", ["tangent.jl"]).done();

  @Command()
  kotlin(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.kt")
    .compile("/usr/local/sdkman/candidates/kotlin/current/bin/kotlinc", ["tangent.kt", "-include-runtime", "-d", "tangent.jar"])
    .run("java", ["-jar", "tangent.jar"]).done();

  @Command()
  scala(CommandArgs args) => TaskBuilder(q, args)
    .save("Tangent.scala")
    .run("/usr/local/sdkman/candidates/scala/current/bin/scala", ["Tangent.scala"]).done();

  @Command()
  swift(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.swift")
    .run("bash", ["-c", "source /opt/Tangent/swiftSetup.sh && swift tangent.swift"]).done();

  @Command()
  typescript(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.ts")
    .compile("tsc", ["tangent.ts"])
    .run("js", ["tangent.js"]).done();

  @Command()
  verilog(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.v")
    .compile("iverilog", ["-o", "tangent", "tangent.v"])
    .run("./tangent").done();

  @Command()
  wasm(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.wast")
    .run("wavm-run", ["tangent.wast"]).done();

  @Command()
  scheme(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.scm")
    .run("sh", ["-c", "scheme --quiet < tangent.scm"]).done();

  @Command()
  awk(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.awk")
    .run("awk", ["-f", "tangent.awk"]).done();

  @Command()
  clojure(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.clj")
    .run("clojure", ["tangent.clj"]).done();

  @Command()
  tibasic(CommandArgs args) => TaskBuilder(q, args, trimCode: true)
    .save("tangent.bas")
    .run("java", ["-cp", "/opt/ti-basic/ti-basic.jar", "com.patrickfeltes.interpreter.Main", "tangent.bas"]).done();

  @Command()
  batch(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.bat")
    .run("wine", ["cmd", "/c", "tangent.bat"]).done();

  @Command()
  racket(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.rkt")
    .run("racket", ["tangent.rkt"]).done();

  @Command()
  rust(CommandArgs args) => TaskBuilder(q, args)
    .save("tangent.rs")
    .compile("rustc", ["-o", "tangent", "tangent.rs"])
    .run("./tangent").done();
}