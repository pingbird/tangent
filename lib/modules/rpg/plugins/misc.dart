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

    mod.re.craft["XP Orb"] = Tuple2([Item("xp", 50)], [Item("xporb")]);
    mod.re.crush["XP Orb"] = Tuple2(Item("xporb"), itGenSingle("xp", start: 50));

    mod.re.craft["millisecond"] = Tuple2([Item("second", 1000)], [Item("millisecond", 1)]);
    mod.re.crush["millisecond"] = Tuple2(Item("millisecond"), itGenSingle("second", start: 1000));

    mod.re.craft["microsecond"] = Tuple2([Item("millisecond", 1000)], [Item("microsecond", 1)]);
    mod.re.crush["microsecond"] = Tuple2(Item("microsecond"), itGenSingle("milliseconds", start: 1000));

    mod.re.craft["nanosecond"] = Tuple2([Item("microsecond", 1000)], [Item("nanosecond", 1)]);
    mod.re.crush["nanosecond"] = Tuple2(Item("nanosecond"), itGenSingle("microsecond", start: 1000));
  }

  @RpgCommand() json(RpgArgs args) {
    return "```" + JsonEncoder.withIndent("  ").convert(args.player.toJson()) + "```";
  }

  @RpgCommand() beg(RpgArgs args) {
    if (args.player.getCooldown("beg")) {
      var cd = args.player.getCooldownDelta("beg");

      var dt = ItemDelta(mod.it);
      if (cd < 0.001) {
        dt.addItem(Item("microsecond", 1000 - (cd * 1000000).floor()));
      } else if (cd < 1) {
        dt.addItem(Item("millisecond", 1000 - (cd * 1000).floor()));
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
}