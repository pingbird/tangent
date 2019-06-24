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
      if (li.item2.count == 1) return "You are missing a ${lin.toString(amount: false)} ( ${li.item1.count} / ${-li.item2.count} )";
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
      if (li.item2.count == 1) return "You are missing a ${lin.toString(amount: false)} ( ${li.item1.count} / ${-li.item2.count} )";
      return "You are missing ${lin.toString(amount: false)} ( ${li.item1.count} / ${-li.item2.count} )";
    }

    dt.addItems(recipe.item2());
    dt.apply(args.player);

    return "Crushed. ( $dt )";
  }
}