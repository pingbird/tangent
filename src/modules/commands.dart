import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

  Future<CommandRes> replace() async {
    cancel();
    if (flushing) await lastFlush?.future;
    return CommandRes(invokeMsg, onCreate)..message = message;
  }

  var cancelled = Completer<Null>();
  Completer<Null> lastFlush = Completer();

  ds.Message message;
  String messageText = "";

  void cancel() {
    if (cancelled.isCompleted) return;
    cancelled.complete();
  }

  bool flushing = false;
  bool dirty = false;
  bool deleted = false;

  int lastMessage;
  int throttle = 100;

  Future flush() async {
    if (cancelled.isCompleted) return;

    if (flushing) {
      dirty = true;
      return;
    }

    flushing = true;

    var time = DateTime.now().millisecondsSinceEpoch;

    if (throttle != 0) {
      if (lastMessage != null) throttle = max(0, throttle - (time - lastMessage));
      if (throttle != 0) await Future.delayed(Duration(milliseconds: throttle));
    }

    if (messageText.length > 2000) {
      messageText = messageText.substring(messageText.length - 2000, messageText.length);
    }

    dirty = false;
    if (messageText != "" && !deleted) {
      if (message == null) {
        message = await invokeMsg.reply(messageText);
        onCreate(message);
      } else {
        await message.edit(content: messageText);
      }
    }

    lastMessage = DateTime.now().millisecondsSinceEpoch;
    throttle = min(5000, throttle + 1000);

    if (dirty) await queue();
    flushing = false;
    lastFlush.complete();
    lastFlush = Completer();
  }

  Future queue() async {
    await flush();
  }

  void set(String msg) async {
    messageText = msg;
    await queue();
  }

  void add(List<int> event) async {
    messageText += Utf8Codec().decode(event, allowMalformed: true);
    await queue();
  }

  Future close() async {
    await flush();
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

  Future<Null> get onCancel => res.cancelled.future;
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
    if (args.isEmpty) return;
    var idx = text.indexOf(RegExp("\\S"), args.first.length);
    var name = args.isEmpty ? "" : args.removeAt(0);
    if (idx == -1) idx = args.isEmpty ? name.length : args.first.length;
    if (commands.containsKey(name)) {
      var c = commands[name];
      if (c.meta.trusted && !trusted) return;

      res ??= CommandRes(msg, (rmsg) {
        responses[rmsg.id] = res;
      });

      if (userResponses.containsKey(msg.m.author.id)) {
        var pmsg = userResponses[msg.m.author.id];
        pmsg.cancel();
        if (pmsg.message != null) responses.remove(pmsg.message.id);
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
      await invoke(msg, res: await res.replace());
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

    if (userResponses.containsKey(msg.m.author.id)) {
      var res = userResponses[msg.m.author.id];
      await res.close();
      userResponses.remove(msg.m.author.id);
      if (res.message != null) {
        responses.remove(res.message.id);
        res.deleted = true;
        await res.message.delete();
      }
    }
  }

  @override unload() async {

  }
}