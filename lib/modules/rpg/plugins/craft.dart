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

  @Command() craft(RpgArgs args) {
    var recipeName = mod.findQuery(args.text, mod.re.craftRecipes.keys, (e) => e);
    if (recipeName == null) return "Could not find recipe";

    var recipe = mod.re.craftRecipes[recipeName];

    var dt = ItemDelta(mod.it)..removeItems(recipe.item1)..addItems(recipe.item2);

    var li = dt.checkApply(args.player);

    if (li != null) {
      var lin = mod.it.get(li.item2);
      if (li.item2.count == 1) return "You are missing a ${lin.toString(amount: false)} ( ${li.item1.count} / ${li.item2.count} )";
      return "You are missing ${lin.toString(amount: false)} ( ${li.item1.count} / ${li.item2.count} )";
    }

    dt.apply(args.player);

    return "Crafted. ( $dt )";
  }

  @Command() crush(RpgArgs args) {
    var recipeName = mod.findQuery(args.text, mod.re.crushRecipes.keys, (e) => e);
    if (recipeName == null) return "Could not find recipe";

    var recipe = mod.re.crushRecipes[recipeName];
    var dt = ItemDelta(mod.it)..removeItem(recipe.item1)..addItems(recipe.item2());
    var li = dt.checkApply(args.player);

    if (li != null) {
      var lin = mod.it.get(li.item2);
      if (li.item2.count == 1) return "You are missing a ${lin.toString(amount: false)} ( ${li.item1.count} / ${li.item2.count} )";
      return "You are missing ${lin.toString(amount: false)} ( ${li.item1.count} / ${li.item2.count} )";
    }

    dt.apply(args.player);

    return "Crafted. ( $dt )";
  }
}