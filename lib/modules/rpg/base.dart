import 'dart:async';
import 'dart:convert';
import 'dart:mirrors' as mirrors;

import 'package:nyxx/nyxx.dart' as ds;

import 'package:tangent/base.dart';
import 'package:tangent/common.dart';
import 'package:tangent/modules/commands.dart';
import 'package:tangent/modules/rpg/data.dart';
import 'package:tangent/modules/rpg/items.dart';
import 'package:pointycastle/digests/md5.dart';

import 'package:tangent/modules/rpg/plugins/inventory.dart';
import 'package:tangent/modules/rpg/plugins/craft.dart';
import 'package:tangent/modules/rpg/plugins/misc.dart';
import 'package:tangent/modules/rpg/plugins/exchange.dart';
import 'package:tangent/modules/rpg/plugins/mining.dart';

class RpgCommand {
  const RpgCommand();
}

typedef RpgCommandFn(RpgArgs args);

abstract class RpgPlugin {
  RpgModule mod;
  Future init() async {}
  Future close() async {}
}

class RpgArgs {
  RpgArgs(this.player, this.cmdArgs) {
    res = cmdArgs.res;
    text = cmdArgs.text;
    msg = cmdArgs.msg;
    list = ArgParse(text, parseFlags: false).list;
  }

  Player player;
  CommandArgs cmdArgs;
  List<String> list;
  String text;
  int idx;
  TangentMsg msg;
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

const rpgGuild = "368249740120424449";

class RpgModule extends TangentModule implements CmdInit {
  var db = RpgDB();
  var it = ItemContext();
  var re = RecipeRegistry();

  var plugins = Set<RpgPlugin>();

  T findQuery<T>(String query, Iterable<T> items, String itemString(T e)) {
    int lowestDist;
    T out;

    int bestScore;
    T scoreOut;

    for (var i in items) {
      var v = itemString(i);

      var dist = levenshtein(v, query, caseSensitive: false);

      if (lowestDist == null || dist < lowestDist) {
        lowestDist = dist;
        out = i;
      }

      var a = v.split("").toList();
      var b = query.split("").toList();
      var offset = 0;

      while (a.isNotEmpty && b.isNotEmpty && a.first.toLowerCase() != b.first.toLowerCase()) {
        offset++;
        a.removeAt(0);
      }

      var len = 0;

      while (a.isNotEmpty && b.isNotEmpty && a.first.toLowerCase() == b.first.toLowerCase()) {
        len++;
        a.removeAt(0);
        b.removeAt(0);
      }

      var score = ((offset / 4) + (10 / (len + 1))).floor();

      if (scoreOut == null || score < bestScore) {
        bestScore = score;
        scoreOut = i;
      }
    }

    if (scoreOut != null && bestScore < lowestDist) return scoreOut;
    if (out != null && lowestDist < 10) return out;

    return null;
  }

  Player findPlayer(String query) {
    var find = <int>[];

    var members = tangent.nyxx.guilds[ds.Snowflake(rpgGuild)].members;

    for (var member in members.values) {
      var id = member.id.toInt();
      if (!db.players.m.containsKey(id)) continue;

      if (
        query == id.toString() ||
        query == "<@$id>" ||
        query == "${member.username}#${member.discriminator}"
      ) return db.players.m[id];

      find.add(id);
    }

    var id = findQuery(query, find, (e) {
      var m = members[ds.Snowflake(e)];
      return m.nickname ?? m.username;
    });

    if (id == null) return null;
    return db.players.m[id];
  }

  Item findItem(String query, List<Item> items) =>
    findQuery(query, items, (e) => it.get(e).name);

  @override init() async {
  }

  @override unload() async {
    await db.close();
  }

  initCmd(CommandsModule mod) async {
    await db.load();
    for (var t in [
      InventoryPlugin,
      CraftPlugin,
      MiscPlugin,
      ExchangePlugin,
      MiningPlugin,
    ]) {
      var tm = mirrors.reflectClass(t);
      var instMirror = tm.newInstance(Symbol(""), []);
      RpgPlugin inst = instMirror.reflectee;
      plugins.add(inst);

      for (var decl in tm.declarations.values) {
        if (decl is mirrors.MethodMirror) for (var m in decl.metadata) {
          if (m.type.isSubclassOf(mirrors.reflectClass(RpgCommand))) {
            var name = mirrors.MirrorSystem.getName(decl.simpleName);
            RpgCommandFn fn = instMirror.getField(decl.simpleName).reflectee;
            mod.commands[name] = CommandEntry(Command(), (args) async {
              args.res.doPing = true;
              var id = args.msg.m.author.id.toInt();
              if (!db.players.m.containsKey(id)) {
                return "You are not registered, use the start command";
              }

              var player = db.players.m[id];

              if (!player.isBanned()) {
                player.applySpam(toHex(MD5Digest().process(Utf8Codec().encode(args.text.trim()))));

                if (player.isBanned()) {
                  var banTime = player.ban - new DateTime.now().millisecondsSinceEpoch;

                  var dt = ItemDelta(it)
                    ..addItem(Item("spam"))
                    ..apply(player);

                  return "You have been banned ${toTime(banTime / 1000.0)} for spamming ( ${dt} )";
                }

                return fn(RpgArgs(player, args));
              }
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

    var dt = ItemDelta(it)
      ..addItem(Item("soul"))
      ..apply(newPlayer);

    return "Profile created ( $dt )";
  }
}