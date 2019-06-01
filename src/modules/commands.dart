import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../main.dart';
import '../common.dart';
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

typedef void _OnMessageCreate(ds.Message message);

class CommandRes extends BasicStringSink implements StreamSink<List<int>>, StringSink {
  TangentMsg invokeMsg;
  _OnMessageCreate onCreate;
  CommandRes(this.invokeMsg, this.onCreate);

  CommandRes replace() {
    cancel();
    return CommandRes(invokeMsg, onCreate)..message = message;
  }

  var cancelled = Completer<Null>();

  ds.Message message;
  String messageText = "";
  Timer msgQueue;

  void cancel() {
    if (cancelled.isCompleted) return;
    cancelled.complete();
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
      messageText = messageText.substring(messageText.length - 2000, messageText.length);
    }

    if (messageText == "") return;

    if (message == null) {
      flushing = true;
      dirty = false;
      message = await invokeMsg.reply(messageText);
      onCreate(message);
      if (dirty) queue();
      flushing = false;
    } else {
      await message.edit(content: messageText);
    }
  }

  void queue() {
    if (msgQueue != null || cancelled.isCompleted) return;
    msgQueue = Timer(Duration(milliseconds: 250), flush);
  }

  void set(String msg) {
    messageText = msg;
    queue();
  }

  void add(List<int> event) {
    messageText += Utf8Codec().decode(event, allowMalformed: true);
    queue();
  }

  Future close() {
    flush();
    cancel();
    return null;
  }

  Future get done => cancelled.future;
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

  Map<ds.Snowflake, CommandRes> responses = {};
  Map<ds.Snowflake, CommandRes> userResponses = {};

  Future invoke(TangentMsg msg, {CommandRes res}) async {
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
    var idx = args.isEmpty ? 0 : text.indexOf(RegExp("\\s"), args.first.length);
    var name = args.isEmpty ? "" : args.removeAt(0);
    if (idx == -1) idx = args.isEmpty ? 0 : args.first.length;
    if (commands.containsKey(name)) {
      var c = commands[name];
      if (c.meta.trusted && !trusted) return;

      res ??= CommandRes(msg, (rmsg) {
        responses[rmsg.id] = res;
      });

      if (userResponses.containsKey(msg.m.author.id)) {
        var pmsg = userResponses[msg.m.author.id].message;
        if (pmsg != null) responses.remove(pmsg.id);
      }

      userResponses[msg.m.author.id] = res;
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

  @override onMessage(TangentMsg msg) => invoke(msg);

  @override onMessageUpdate(TangentMsg oldMsg, TangentMsg msg) async {
    if (userResponses.containsKey(msg.m.author.id)) {
      var res = userResponses[msg.m.author.id];
      if (msg.m.id != res.invokeMsg.m.id) return;
      await invoke(msg, res: res.replace());
    }
  }

  @override void onMessageDelete(TangentMsg msg) async {
    if (responses.containsKey(msg.m.id)) {
      var res = responses[msg.m.id];
      responses.remove(msg.m.id);
      if (userResponses.containsKey(res.invokeMsg.m.author.id)) {
        userResponses.remove(res.invokeMsg.m.author.id);
      }
    }

    if (userResponses.containsKey(msg.m.id)) {
      var res = userResponses[msg.m.id];
      await res.close();
      userResponses.remove(msg.m.id);
      if (res.message != null) {
        responses.remove(res.message.id);
        await res.message.delete();
      }
    }
  }

  @override unload() async {

  }
}