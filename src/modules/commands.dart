import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../main.dart';
import 'package:nyxx/nyxx.dart' as ds;
import 'dart:mirrors' as mirrors;

typedef dynamic CommandHandler(CommandArgs args);

class CommandEntry {
  CommandEntry(this.meta, this.cb);
  Command meta;
  CommandHandler cb;
}

class Command {
  const Command({this.alias, this.trusted = false});
  final List<String> alias;
  final bool trusted;
}

class CommandRes implements StreamSink<List<int>>, StringSink {
  TangentMsg invokeMsg;
  CommandRes(this.invokeMsg);

  var _cancel = StreamController<Null>.broadcast();
  bool cancelled = false;

  ds.Message message;
  String messageText = "";
  Timer msgQueue;

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    _cancel.add(null);
  }

  bool flushing = false;
  bool dirty = false;

  flush() async {
    if (flushing) {
      dirty = true;
      return;
    }

    msgQueue?.cancel();
    msgQueue = null;

    if (messageText.length > 2000) {
      messageText = messageText.substring(0, 2000);
    }

    if (messageText == "") return;

    if (message == null) {
      flushing = true;
      dirty = false;
      message = await invokeMsg.reply(messageText);
      if (dirty) queue();
      flushing = false;
    } else {
      await message.edit(content: messageText);
    }
  }

  void queue() {
    if (msgQueue != null || cancelled) return;
    msgQueue = Timer(Duration(milliseconds: 100), flush);
  }

  void set(String msg) {
    messageText = msg;
    queue();
  }

  void add(List<int> event) {
    messageText += Utf8Codec().decode(event, allowMalformed: true);
    queue();
  }

  addError(Object error, [StackTrace stackTrace]) {
    throw error;
  }

  Future addStream(Stream<List<int>> stream) {
    stream.listen(add);
    return null;
  }

  Future close() {
    flush();
    cancel();
    return null;
  }

  Future get done => _cancel.stream.first;

  void write(Object obj) {
    add(Utf8Codec().encode("$obj"));
  }

  void writeAll(Iterable objects, [String separator = ""]) {
    write(objects.join(separator));
  }

  void writeCharCode(int charCode) {
    add([charCode]);
  }

  void writeln([Object obj = ""]) {
    write("${obj}\n");
  }
}

class CommandArgs {
  CommandArgs(this.msg, this.res, this.argText, this.args);
  TangentMsg msg;
  CommandRes res;
  String argText;

  int idx = 0;
  List<String> args;

  int expectInt() {
    if (idx == args.length) throw "Integer expected";
    var e = args[idx++];
    return int.tryParse(e) ?? (throw "Integer expected");
  }

  int expectPositiveInt() {
    var n = expectInt();
    if (n < 0) throw "Integer must be positive";
    return n;
  }

  num expectNum() {
    if (idx == args.length) throw "Number expected";
    var e = args[idx++];
    return num.tryParse(e) ?? (throw "Number expected");
  }

  String expectString() {
    if (idx == args.length) throw "String expected";
    return args[idx++];
  }

  void expectNone() {
    if (idx != args.length) throw "Too many arguments";
  }
}

class CommandsModule extends TangentModule {
  Map<String, CommandEntry> commands;

  @override init() async {
    commands = {};
    for (var m in modules) {
      var mod = mirrors.reflect(m);
      var modType = mirrors.reflectClass(m.runtimeType);
      for (var decl in modType.declarations.values) {
        if (decl is mirrors.MethodMirror) for (var meta in decl.metadata) {
          var r = meta.reflectee;
          if (r is Command) {
            List<String> alias;
            if (r.alias == null) {
              alias = [mirrors.MirrorSystem.getName(decl.simpleName)];
            } else alias = r.alias;
            CommandHandler cb = mod.getField(decl.simpleName).reflectee;
            for (var n in alias) commands[n] = CommandEntry(r, cb);
            break;
          }
        }
      }
    }
  }

  @override onReady() {}

  @override onMessage(TangentMsg msg) async {
    print("got message '${msg.m.content}'");
    if (msg.m.channel is! ds.TextChannel) return;
    var channel = msg.m.channel as ds.TextChannel;
    if (channel.guild.id.id.toString() != "368249740120424449") return;

    var botChannel = "583237985131036702";
    var trustedRole = "368249935281389578";
    ds.Member u = msg.m.author;
    bool trusted = u.roles.any((e) => e.id.id.toString() == trustedRole);

    if (!trusted && msg.m.channel.id.id.toString() != botChannel) return;

    const prefix = "α";
    var text = msg.m.content.trim();
    if (text.startsWith(prefix)) {
      text = text.substring(prefix.length);
    } else if (text.startsWith("<@!${nyxx.self.id}>")) {
      text = text.substring("<@!${nyxx.self.id}>".length).trimLeft();
    } else if (text.startsWith("<@${nyxx.self.id}>")) {
      text = text.substring("<@${nyxx.self.id}>".length).trimLeft();
    } else return;
    var args = text.split(RegExp("\\s+"));
    var name = args.isEmpty ? "" : args.removeAt(0);
    var idx = args.isEmpty ? 0 : text.indexOf(RegExp("\\s"), args.first.length);
    if (idx == -1) idx = args.first.length;
    if (commands.containsKey(name)) {
      var c = commands[name];
      if (c.meta.trusted && !trusted) return;
      var res = CommandRes(msg);
      try {
        await commands[name].cb(CommandArgs(msg, res, text.substring(idx), args));
      } catch (e) {
        res.writeln("Error: $e");
        await res.close();
        rethrow;
      }
      await res.close();
    }
  }
}