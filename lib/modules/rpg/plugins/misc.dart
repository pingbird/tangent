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

    mod.re.craftRecipes["XP Orb"] = Tuple2([Item("xp", 50)], [Item("xporb")]);
    mod.re.crushRecipes["XP Orb"] = Tuple2(Item("xporb"), itGenSingle("xp", start: 50));
  }

  @Command() beg(CommandArgs args) {
    
  }
}