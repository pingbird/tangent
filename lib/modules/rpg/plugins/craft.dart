import 'dart:math';

import 'package:tangent/base.dart';
import 'package:tangent/common.dart';
import 'package:tangent/modules/commands.dart';
import 'package:tangent/modules/rpg/data.dart';
import 'package:tangent/modules/rpg/base.dart';
import 'package:tangent/modules/rpg/items.dart';

import 'package:nyxx/nyxx.dart' as ds;
import 'package:tuple/tuple.dart';

class CraftPlugin extends RpgPlugin {
  init() async {}

  @RpgCommand() craft(RpgArgs args) {
    var recipeName = mod.findQuery(args.text, mod.re.craft.keys, (e) => e);
    if (recipeName == null) return "Could not find recipe";

    var recipe = mod.re.craft[recipeName];

    var dt = ItemDelta(mod.it)..removeItems(recipe.item1);

    var li = dt.checkApply(args.player);

    if (li != null) {
      var lin = mod.it.get(li.item2);
      if (li.item2.count == BigInt.one) return "You are missing a ${lin.toString(amount: false)} ( ${li.item1.count} / ${-li.item2.count} )";
      return "You are missing ${lin.toString(amount: false)} ( ${li.item1.count} / ${-li.item2.count} )";
    }

    dt.addItems(recipe.item2);
    dt.apply(args.player);

    return "Crafted. ( $dt )";
  }

  @RpgCommand() crush(RpgArgs args) {
    var recipeName = mod.findQuery(args.text, mod.re.crush.keys, (e) => e);
    if (recipeName == null) return "Could not find recipe";

    var recipe = mod.re.crush[recipeName];
    var dt = ItemDelta(mod.it)..removeItem(recipe.item1);
    var li = dt.checkApply(args.player);

    if (li != null) {
      var lin = mod.it.get(li.item2);
      if (li.item2.count == BigInt.one) return "You are missing a ${lin.toString(amount: false)} ( ${li.item1.count} / ${-li.item2.count} )";
      return "You are missing ${lin.toString(amount: false)} ( ${li.item1.count} / ${-li.item2.count} )";
    }

    dt.addItems(recipe.item2());
    dt.apply(args.player);

    return "Crushed. ( $dt )";
  }

  @RpgCommand() refine(RpgArgs args) {
    var time = DateTime.now().millisecondsSinceEpoch;
    var rp = args.player.refineProgress;

    var omsg = <String>[];

    if (rp != null && rp.time < time) {
      args.player.refineProgress = null;
      var dt = ItemDelta(mod.it);
      dt.addItems(rp.items);
      dt.apply(args.player);
      omsg.add("Finished refining ${rp.name} ( $dt )");
      rp = null;
    }

    if (rp != null)
      omsg.add("Refine in progress, will be done in ${toTime((rp.time - time) / 1000)}");

    if (args.list.isNotEmpty && rp == null) {
      var it = mod.findItem(args.text, args.player.items);
      if (it == null) {
        omsg.add("No such item '${args.text}'");
      } else if (!mod.re.refine.containsKey(it.id)) {
        omsg.add("Cannot refine item.");
      } else {
        var dt = ItemDelta(mod.it)..removeItem(it.copy(count: BigInt.one));

        if (dt.checkApply(args.player) != null) {
          omsg.add("You do not have any ${mod.it.get(it, count: BigInt.two).toString(amount: false)}.");
        } else {
          var rd = mod.re.refine[it.id];

          var ndt = (((Random().nextDouble() * (rd.maxTime - rd.minTime)) + rd.minTime) * 1000).floor();

          args.player.refineProgress = RefineProgress()
            ..name = mod.it.get(it, count: BigInt.one).toString(amount: false)
            ..time = time + ndt
            ..items = rd.output().toList();

          dt.apply(args.player);
          omsg.add("Refining for ${toTime(ndt / 1000)} ( $dt )");
        }
      }
    }

    if (omsg.isEmpty) return "No refine in progress.";

    return omsg.join("\n");
  }
}