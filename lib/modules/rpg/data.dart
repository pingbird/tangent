import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';

import 'package:json_annotation/json_annotation.dart';
import 'package:tangent/modules/rpg/base.dart';

part "data.g.dart";

typedef Map<String, dynamic> _ToJson<T>(T t);
typedef T _FromJson<T>(Map<String, dynamic> m);

class RpgTable<T extends RpgTableElm> {
  String name;
  _ToJson<T> elmToJson;
  _FromJson<T> elmFromJson;
  RpgTable(this.name, this.elmToJson, this.elmFromJson);

  Future load() async {
    var playersDir = Directory("db/rpg/$name");
    if (!await playersDir.exists()) playersDir = await playersDir.create(recursive: true);

    await Future.wait((await playersDir.list().toList()).map((p) async {
      if (p is File) {
        var n = int.tryParse(p.uri.pathSegments.last);
        if (n == null) return;
        m[n] = elmFromJson(jsonDecode(await p.readAsString()))
          ..table = this
          ..id = n;
      }
    }));
  }

  Map<int, T> m = {};

  var saveReq = StreamController<Null>.broadcast();
  var saveQueue = Set<int>();
  var saveDone = Completer<Null>();

  void saveTask() async {
    while (!saveReq.isClosed) {
      try {
        await saveReq.stream.first;
      } on StateError catch(e) {
        break;
      }

      await Future.delayed(Duration(milliseconds: 100));

      while (saveQueue.isNotEmpty) {
        var toSave = saveQueue.toList();
        saveQueue.clear();

        await Future.wait(toSave.map((id) =>
          File("db/rpg/$name/$id").writeAsString(jsonEncode(elmToJson(m[id])))
        ));
      }
    }

    saveDone.complete();
  }

  Future close() async {
    await saveReq.close();
    await saveDone.future;
  }
}

class RpgTableElm {
  @JsonKey(ignore: true) int id;
  @JsonKey(ignore: true) RpgTable table;
  void save() {
    table.saveQueue.add(id);
    table.saveReq.add(null);
  }
}

class RpgDB {
  Future load() async {
    await Future.wait([
      players
    ].map((m) async {
      await m.load();
      m.saveTask();
    }));
  }

  var players = RpgTable("players", _$PlayerToJson, _$PlayerFromJson);

  Future close() async {
    await Future.wait([
      players.close(),
      // ...
    ]);
  }
}

@JsonSerializable() class Item {
  Item.nil();
  Item(this.id, [this.count, this.meta]) {
    count ??= 1;
    meta ??= {};
  }

  String id;
  int count;
  Map<String, String> meta;

  factory Item.fromJson(Map<String, dynamic> json) => _$ItemFromJson(json);
  Map<String, dynamic> toJson() => _$ItemToJson(this);
}

@JsonSerializable() class Player extends RpgTableElm {
  Player();
  int level = 0;
  List<Item> items = [];
  Map<String, int> cooldowns = {};
  Map<String, String> meta = {};
  int ban;
  int lastMsgTime;
  String lastMsgText;
  double spam;
  int strike = 0;

  bool getCooldown(String name) {
    cooldowns ??= {};
    if (!cooldowns.containsKey(name)) return false;
    if (new DateTime.now().microsecondsSinceEpoch > cooldowns[name]) {
      cooldowns.remove(name);
      save();
      return false;
    }
    return true;
  }

  double getCooldownDelta(String name) {
    cooldowns ??= {};
    if (!cooldowns.containsKey(name)) return double.negativeInfinity;
    return (cooldowns[name] - new DateTime.now().microsecondsSinceEpoch) / 1000000.0;
  }

  void setCooldown(String name, double offset) {
    cooldowns ??= {};
    cooldowns[name] = new DateTime.now().microsecondsSinceEpoch + (offset * 1000000).toInt();
    save();
  }

  bool isBanned() => ban != null && DateTime.now().millisecondsSinceEpoch < ban;

  void applySpam(String text) {
    if (ban != null && new DateTime.now().millisecondsSinceEpoch >= ban) ban = null;
    lastMsgTime ??= new DateTime.now().millisecondsSinceEpoch - 100000;
    spam ??= 0.0;
    spam = max(0.0, (spam - ((new DateTime.now().millisecondsSinceEpoch - lastMsgTime) / 1000)) + (lastMsgText == text ? 2 : 1));
    lastMsgText = text;
    if (spam > 2.5) {
      ban = new DateTime.now().millisecondsSinceEpoch + 120000;
      strike = (strike ?? 0) + 1;
    }
    lastMsgTime = new DateTime.now().millisecondsSinceEpoch;
  }

  factory Player.fromJson(Map<String, dynamic> json) => _$PlayerFromJson(json);
  Map<String, dynamic> toJson() => _$PlayerToJson(this);
}