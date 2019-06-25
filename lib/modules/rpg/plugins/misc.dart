import 'dart:convert';
import 'dart:math';

import 'package:tangent/base.dart';
import 'package:tangent/common.dart';
import 'package:tangent/modules/commands.dart';
import 'package:tangent/modules/rpg/data.dart';
import 'package:tangent/modules/rpg/base.dart';
import 'package:tangent/modules/rpg/items.dart';

import 'package:nyxx/nyxx.dart' as ds;
import 'package:tuple/tuple.dart';

class MiscPlugin extends RpgPlugin {
  init() async {
    mod.it.register("soul", plural: "souls");
    mod.it.register("xp", name: "XP");
    mod.it.register("xp_orb", name: "XP Orb", plural: "XP Orbs");
    mod.it.register("spam", plural: "spams");

    mod.it.register("second", plural: "seconds");
    mod.it.register("millisecond", plural: "milliseconds");
    mod.it.register("microsecond", plural: "microseconds");
    mod.it.register("nanosecond", plural: "nanoseconds");

    mod.it.register("lint");

    mod.re.craft["XP Orb"] = Tuple2([Item.int("xp", 50)], [Item.int("xporb")]);
    mod.re.crush["XP Orb"] = Tuple2(Item.int("xporb"), itGenSingle("xp", start: 50));

    mod.re.craft["millisecond"] = Tuple2([Item.int("second", 1000)], [Item.int("millisecond", 1)]);
    mod.re.crush["millisecond"] = Tuple2(Item.int("millisecond"), itGenSingle("second", start: 1000));

    mod.re.craft["microsecond"] = Tuple2([Item.int("millisecond", 1000)], [Item.int("microsecond", 1)]);
    mod.re.crush["microsecond"] = Tuple2(Item.int("microsecond"), itGenSingle("milliseconds", start: 1000));

    mod.re.craft["nanosecond"] = Tuple2([Item.int("microsecond", 1000)], [Item.int("nanosecond", 1)]);
    mod.re.crush["nanosecond"] = Tuple2(Item.int("nanosecond"), itGenSingle("microsecond", start: 1000));
  }

  @RpgCommand() json(RpgArgs args) {
    return "```" + JsonEncoder.withIndent("  ").convert(args.player.toJson()) + "```";
  }

  @RpgCommand() beg(RpgArgs args) {
    if (args.player.getCooldown("beg")) {
      var cd = args.player.getCooldownDelta("beg");

      var dt = ItemDelta(mod.it);
      if (cd < 0.001) {
        dt.addItem(Item.int("microsecond", 1000 - (cd * 1000000).floor()));
      } else if (cd < 1) {
        dt.addItem(Item.int("millisecond", 1000 - (cd * 1000).floor()));
      }

      if (dt.isNotEmpty) dt.apply(args.player);

      return "You must wait ${toTime(cd)} before begging again.${dt.isEmpty ? "" : " ( $dt )"}";
    }
    args.player.setCooldown("beg", 1200);

    if (Random().nextInt(6) == 5) {
      var dt = ItemDelta(mod.it)..removeItems(itGenDist({
        itGenSingle("dollar", end: 100, curve: expCurve(3)): 4.0,
      })());
      dt.apply(args.player);
      return "You got mugged ( $dt )";
    } else {
      var items = itGenDist({
        () => []: 1.0,
        itGenSingle("dollar", end: 100, curve: expCurve(3)): 4.0,
      })();

      if (items.isEmpty) return "You beg and get nothing.";

      var dt = ItemDelta(mod.it)
        ..addItems(items)
        ..addItems(itGenSingle("xp", start: 0, end: 10, curve: expCurve(3))());

      dt.apply(args.player);
      return "You got some change ( $dt )";
    }
  }

  @RpgCommand() rank(RpgArgs args) {
    String itName;
    if (args.list.isEmpty) {
      itName = "dollar";
    } else {
      itName = mod.findQuery(args.text, mod.it.descs.keys, (e) => e);
      if (itName == null) {
        return "Could not find item.";
      }
    }

    var leaderboard = (mod.db.players.m.values.where((e) => e.getItemCount(itName) != BigInt.zero).toList()
      ..sort((a, b) => b.getItemCount(itName).compareTo(a.getItemCount(itName)))
    ).take(10);

    var first = args.msg.m.guild.members[ds.Snowflake(leaderboard.first.id)];

    if (leaderboard.isEmpty) return "Nobody has that item.";

    var itf = mod.it.get(Item(itName));
    var oe = ds.EmbedBuilder();

    oe.title = "Top ${itf.toString(amount: false)} rankings:";
    oe.thumbnailUrl = first?.avatarURL();

    int i = 1;
    for (var p in leaderboard) {
      var name = "${p.id}";
      var member = args.msg.m.guild.members[ds.Snowflake(p.id)];
      if (member != null) name = member.nickname ?? member.username;
      oe.addField(
        name: "#${i++} - ${name}",
        content: "${mod.it.get(Item(itName), count: p.getItemCount(itName))}",
        inline: true,
      );
    }

    args.res.addEmbed(oe);
  }
}