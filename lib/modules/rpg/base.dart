import 'dart:async';
import 'dart:mirrors' as mirrors;

import 'package:tangent/base.dart';
import 'package:tangent/common.dart';
import 'package:tangent/modules/commands.dart';
import 'package:tangent/modules/rpg/data.dart';
import 'package:tangent/modules/rpg/items.dart';

import 'package:tangent/modules/rpg/plugins/inventory.dart';

class RpgCommand {}

typedef RpgCommandFn(RpgArgs args);

abstract class RpgPlugin {
  RpgModule mod;
  Future init() async {}
  Future close() async {}
}

class RpgArgs {
  RpgArgs(this.player, this.cmdArgs) {
    res = cmdArgs.res;
    list = ArgParse(cmdArgs.text, parseFlags: false).list;
  }

  Player player;
  CommandArgs cmdArgs;
  List<String> list;
  int idx;
  CommandRes res;

  int getInt() {
    if (idx == list.length) throw "Integer expected";
    var e = list[idx++];
    return int.tryParse(e) ?? (throw "Integer expected");
  }

  int getUInt() {
    var n = getInt();
    if (n < 0) throw "Integer must be positive";
    return n;
  }

  num getNum() {
    if (idx == list.length) throw "Number expected";
    var e = list[idx++];
    return num.tryParse(e) ?? (throw "Number expected");
  }

  String getString() {
    if (idx == list.length) throw "String expected";
    return list[idx++];
  }

  void expectNone() {
    if (idx != list.length) throw "Too many arguments";
  }
}

typedef RpgCmdCallback(RpgArgs args);

class RpgModule extends TangentModule implements CmdInit {
  var db = RpgDB();
  var it = ItemContext();

  var plugins = Set<RpgPlugin>();

  @override init() async {
    await db.load();
  }

  @override unload() async {
    await db.close();
  }

  initCmd(CommandsModule mod) async {
    for (var t in [
      InventoryPlugin,
    ]) {
      var tm = mirrors.reflectClass(t);
      RpgPlugin inst = tm.newInstance(Symbol(""), []).reflectee;

      for (var decl in tm.declarations.values) {
        if (decl is mirrors.FunctionTypeMirror) for (var m in decl.metadata) {
          if (m.type.isSubclassOf(mirrors.reflectClass(RpgCommand))) {
            RpgCommandFn fn = decl.getField(decl.simpleName).reflectee;
            mod.commands[mirrors.MirrorSystem.getName(decl.simpleName)] = CommandEntry(Command(), (args) async {
              var id = args.msg.m.author.id.toInt();
              if (!db.players.m.containsKey(id)) {
                return "You are not registered, use the start command";
              }
              var player = db.players.m[id];
              return fn(RpgArgs(player, args));
            });
          }
        }
      }

      inst.mod = this;
    }

    for (var p in plugins) {
      await p.init();
    }
  }

  @Command() start(CommandArgs args) async {
    var id = args.msg.m.author.id.toInt();
    if (db.players.m.containsKey(id)) {
      return "You are already registered";
    }

    var newPlayer = Player()
      ..id = id
      ..table = db.players;

    db.players.m[id] = newPlayer;

    newPlayer.save();

    return "Profile created!";
  }
}