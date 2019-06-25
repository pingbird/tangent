import 'package:tangent/base.dart';
import 'package:tangent/common.dart';
import 'package:tangent/modules/commands.dart';
import 'package:tangent/modules/rpg/data.dart';
import 'package:tangent/modules/rpg/base.dart';
import 'package:tangent/modules/rpg/items.dart';

import 'package:nyxx/nyxx.dart' as ds;
import 'package:tuple/tuple.dart';

class MiningPlugin extends RpgPlugin {
  init() async {
    mod.it.register("dust");
    mod.it.register("coal");
    mod.it.register("iron");
    mod.it.register("steel");
    mod.it.register("gold");
    mod.it.register("cobblestone");
    mod.it.register("gunpowder");
    mod.it.register("sapphire", plural: "sapphires");
    mod.it.register("microsapphire", plural: "microsapphires");
    mod.it.register("ruby", plural: "rubies");
    mod.it.register("microruby", plural: "microrubies");
    mod.it.register("emerald", plural: "emeralds");
    mod.it.register("microemerald", plural: "microemeralds");
    mod.it.register("diamond", plural: "diamonds");
    mod.it.register("microdiamond", plural: "microemeralds");

    mod.re.refine["cobblestone"] = RefineRecipe(30, 80, itGenDist({
      itGenSingle("dust", end: 10): 800,
      itGenSingle("coal"): 200,
      itGenSingle("iron"): 100,
      itGenSingle("gold"): 50,
      itGenSingle("microsapphire"): 50,
      itGenSingle("microruby"): 50,
      itGenSingle("microemerald"): 50,
      itGenSingle("microdiamond"): 10,
    }));

    mod.re.refine["coal"] = RefineRecipe(60, 120, itGenDist({
      itGenSingle("dust", end: 10): 10,
      itGenSingle("gunpowder"): 20,
    }));

    mod.re.refine["dust"] = RefineRecipe(10, 60, itGenDist({
      itGenSingle("dust"): 25,
      itGenSingle("microdiamond"): 1,
    }));

    mod.re.refine["iron"] = RefineRecipe(60, 120, itGenDist({
      itGenSingle("steel") : 15,
      itGenSingle("dust", end: 10): 1,
    }));

    mod.re.crush["cobblestone"] = Tuple2(
      Item("cobblestone"), itGenSingle("dust", end: 10)
    );

    mod.re.crush["sapphire"] = Tuple2(
      Item("sapphire"), itGenSingle("microsaphire", start: 5, end: 10),
    );

    mod.re.crush["emerald"] = Tuple2(
      Item("emerald"), itGenSingle("microemerald", start: 5, end: 10),
    );

    mod.re.crush["ruby"] = Tuple2(
      Item("ruby"), itGenSingle("microruby", start: 5, end: 10),
    );

    mod.re.crush["diamond"] = Tuple2(
      Item("diamond"), itGenSingle("microdiamond", start: 5, end: 10),
    );

    mod.re.craft["sapphire"] = Tuple2(
      [Item.int("microsapphire", 8)], [Item("sapphire")]
    );

    mod.re.craft["emerald"] = Tuple2(
      [Item.int("microemerald", 8)], [Item("emerald")]
    );

    mod.re.craft["ruby"] = Tuple2(
      [Item.int("microruby", 8)], [Item("ruby")]
    );

    mod.re.craft["diamond"] = Tuple2(
      [Item.int("microdiamond", 8)], [Item("diamond")]
    );
  }

  @RpgCommand() mine(RpgArgs args) {
    if (args.player.getCooldown("mine")) {
      return "You must wait ${toTime(args.player.getCooldownDelta("mine"))} before mining again.";
    }

    args.player.setCooldown("mine", 60);

    var it = itGenDist({
      itGenAll([
        itGenSingle("dust", end: 10),
        itGenSingle("xp", start: 0, end: 1, curve: expCurve(3)),
      ]): 500,

      itGenAll([
        itGenSingle("coal", end: 10, curve: expCurve(3)),
        itGenSingle("xp", start: 0, end: 10, curve: expCurve(3)),
      ]): 200,

      itGenAll([
        itGenSingle("iron", end: 10, curve: expCurve(3)),
        itGenSingle("xp", start: 0, end: 20, curve: expCurve(3)),
      ]): 100,

      itGenAll([
        itGenSingle("gold", end: 10, curve: expCurve(3)),
        itGenSingle("xp", start: 0, end: 30, curve: expCurve(3)),
      ]): 50,

      itGenAll([
        itGenSingle("sapphire", end: 10, curve: expCurve(3)),
        itGenSingle("xp", start: 0, end: 30, curve: expCurve(3)),
      ]): 20,

      itGenAll([
        itGenSingle("ruby", end: 10, curve: expCurve(3)),
        itGenSingle("xp", start: 0, end: 30, curve: expCurve(3)),
      ]): 20,

      itGenAll([
        itGenSingle("emerald", end: 10, curve: expCurve(3)),
        itGenSingle("xp", start: 0, end: 30, curve: expCurve(3)),
      ]): 20,

      itGenAll([
        itGenSingle("diamond", end: 10, curve: expCurve(3)),
        itGenSingle("xp", start: 0, end: 50, curve: expCurve(3)),
      ]): 10,
    })();

    var dt = ItemDelta(mod.it);
    dt.addItems(it);
    dt.apply(args.player);

    return "Mined. ( $dt )";
  }
}