import 'package:tangent/base.dart';
import 'package:tangent/common.dart';
import 'package:tangent/modules/commands.dart';
import 'package:tangent/modules/rpg/data.dart';
import 'package:tangent/modules/rpg/base.dart';

class InventoryPlugin extends RpgPlugin {
  init() async {
    mod.it.register("soul", plural: "souls");
    mod.it.register("xp", name: "XP");
    mod.it.register("xp_orb", name: "XP Orb", plural: "XP Orbs");
  }
}

