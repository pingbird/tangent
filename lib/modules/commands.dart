import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:yaml/yaml.dart';

import 'package:tangent/base.dart';
import 'package:tangent/common.dart';
import 'package:tangent/modules/commands.dart';
import 'package:nyxx/nyxx.dart' as ds;
import 'dart:mirrors' as mirrors;

typedef dynamic CommandHandler(CommandArgs args);

class CommandEntry {
  CommandEntry(this.meta, this.cb);
  Command meta;
  CommandHandler cb;
}

class Command {
  const Command({this.alias, this.trusted = false, this.admin = false, this.canPing = false});
  final List<String> alias;
  final bool trusted;
  final bool admin;
  final bool canPing;
}

typedef void _OnMessageCreate(ds.Message message);

class CommandRes extends BasicStringSink implements StreamSink<List<int>>, StringSink {
  TangentMsg invokeMsg;
  _OnMessageCreate onCreate;
  bool canPing;

  CommandRes(this.invokeMsg, this.onCreate, this.canPing);

  Future<CommandRes> replace() async {
    cancel();
    if (flushing) await lastFlush?.future;
    return CommandRes(invokeMsg, onCreate, canPing)..message = message;
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

  String get dbgId => invokeMsg.m.id.toString().substring(0, 5);

  Future flush() async {
    if (!cancelled.isCompleted) dirty = true;
    if (flushing) return;
    flushing = true;

    while (dirty && !deleted) {
      var time = DateTime.now().millisecondsSinceEpoch;

      if (throttle != 0) {
        if (lastMessage != null)
          throttle = max(0, throttle - (time - lastMessage));
        if (throttle != 0) await Future.delayed(
            Duration(milliseconds: throttle));
      }

      if (!canPing) {
        messageText = messageText.replaceAllMapped(RegExp(r'<@(\d+)>'), (m) => "<@!${m.group(1)}>");
      }

      if (messageText.length > 2000) {
        messageText = messageText.substring(
            messageText.length - 2000, messageText.length);
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
    }

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

  void addError(Object error, [StackTrace stackTrace]) {
    stderr.writeln("/// CommandRes Error ///");
    stderr.writeln(error);
    stderr.writeln(stackTrace);
    cancel();
  }
}

class CommandArgs {
  CommandArgs(this.msg, this.res, this.text, this.list);
  TangentMsg msg;
  CommandRes res;
  String text;

  int idx = 0;
  List<String> list;

  int expectInt() {
    if (idx == list.length) throw "Integer expected";
    var e = list[idx++];
    return int.tryParse(e) ?? (throw "Integer expected");
  }

  int expectPositiveInt() {
    var n = expectInt();
    if (n < 0) throw "Integer must be positive";
    return n;
  }

  num expectNum() {
    if (idx == list.length) throw "Number expected";
    var e = list[idx++];
    return num.tryParse(e) ?? (throw "Number expected");
  }

  String expectString() {
    if (idx == list.length) throw "String expected";
    return list[idx++];
  }

  void expectNone() {
    if (idx != list.length) throw "Too many arguments";
  }

  Future<Null> get onCancel => res.cancelled.future;
}

abstract class CmdInit {
  void initCmd(CommandsModule mod);
}

class CommandsModule extends TangentModule {
  Map<String, CommandEntry> commands;

  void loadCommands(dynamic m) {
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

    if (m is CmdInit) m.initCmd(this);
  }

  @override init() async {
    commands = {};
    for (var m in tangent.modules) loadCommands(m);
  }

  @override onReady() {}

  Map<ds.Snowflake, CommandRes> responses = {};
  Map<ds.Snowflake, CommandRes> userResponses = {};

  Future invokeMsg(TangentMsg msg, {CommandRes res}) async {
    if (msg.m.channel is! ds.TextChannel) return;
    var channel = msg.m.channel as ds.TextChannel;
    if (channel.guild.id.id.toString() != "368249740120424449") return;

    var botChannel = "583237985131036702";
    var trustedRole = "368249904658644992";
    var adminRole = "368249923222634496";
    ds.Member u = msg.m.author;
    bool userTrusted = u.roles.any((e) => e.id.id.toString() == trustedRole);
    bool userAdmin = u.roles.any((e) => e.id.id.toString() == trustedRole);

    if (!userAdmin && msg.m.channel.id.id.toString() != botChannel) return;

    var prefixes = (tangent.data["prefixes"] as YamlList).map((d) => d.toString()).toList();
    prefixes.addAll([
      "<@!${tangent.nyxx.self.id}>", "<@${tangent.nyxx.self.id}>",
    ]);

    var text = msg.m.content.trim();

    bool match = false;
    for (var prefix in prefixes) {
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length).trimLeft();
        match = true;
        break;
      }
    }

    if (!match) return;
    var args = text.split(RegExp("\\s+"));
    if (args.isEmpty) return;
    var idx = text.indexOf(RegExp("\\S"), args.first.length);
    var name = args.isEmpty ? "" : args.removeAt(0).toLowerCase();
    if (idx == -1) idx = args.isEmpty ? name.length : args.first.length;
    if (commands.containsKey(name)) {
      var c = commands[name];
      if (c.meta.trusted && !userTrusted) return;
      if (c.meta.admin && !userAdmin) return;

      res ??= CommandRes(msg, (rmsg) {
        responses[rmsg.id] = res;
      }, c.meta.canPing);

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

  @override onMessage(TangentMsg msg) => invokeMsg(msg);

  @override onMessageUpdate(TangentMsg oldMsg, TangentMsg msg) async {
    if (userResponses.containsKey(msg.m.author.id)) {
      var res = userResponses[msg.m.author.id];
      if (msg.m.id != res.invokeMsg.m.id) return;
      await invokeMsg(msg, res: await res.replace());
    }
  }

  @override void onMessageDelete(TangentMsg msg) async {
    if (responses.containsKey(msg.id)) {
      var res = responses[msg.id];
      responses.remove(msg.id);
      if (userResponses.containsKey(res.invokeMsg.m.author.id)) {
        userResponses.remove(res.invokeMsg.m.author.id);
      }
    }

    if (userResponses.containsKey(msg?.m?.author?.id)) {
      var res = userResponses[msg.m.author.id];
      if (msg.id == res.invokeMsg.id) {
        await res.close();
        userResponses.remove(msg.m?.author?.id);
        if (res.message != null) {
          responses.remove(res.message.id);
          res.deleted = true;
          await res.message.delete();
        }
      }
    }
  }

  @override unload() async {

  }
}