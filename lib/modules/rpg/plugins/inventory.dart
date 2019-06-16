import 'package:tangent/base.dart';
import 'package:tangent/common.dart';
import 'package:tangent/modules/commands.dart';
import 'package:tangent/modules/rpg/data.dart';
import 'package:tangent/modules/rpg/base.dart';
import 'package:tangent/modules/rpg/items.dart';

import 'package:nyxx/nyxx.dart' as ds;

class InventoryPlugin extends RpgPlugin {
  @RpgCommand() inv(RpgArgs args) {
    return args.player.items.isEmpty ? "Nothing." : args.player.items.map((i) => mod.it.get(i)).join(", ");
  }

  @RpgCommand() give(RpgArgs args) {
    const usageText = "Usage: `give <user> <amount> <item>`";

    if (args.list.length < 3) return usageText;

    var toPlayer = mod.findPlayer(args.list[0]);
    if (toPlayer == null) return "Could not find player.";

    var it = mod.findItem(args.list.skip(2).join(" "), args.player.items);
    if (it == null) return "You don't have any of that.";

    if (args.list[1] != "*" && args.list[1] != "all") {
      var amount = int.tryParse(args.list[1]);
      if (amount == null || amount < 1) return "Amount must be an integer greater than 1";
      it = it.copy(count: amount);
    }

    var dt = ItemDelta(mod.it)..removeItem(it);

    if (dt.checkApply(args.player) != null) {
      var itName = mod.it.get(it).toString(amount: false);
      if (it.count == 1) {
        return "You do not have a $itName";
      } else {
        return "You do not have enough $itName";
      }
    }

    (-dt).apply(toPlayer);
    dt.apply(args.player);

    var author = args.res.invokeMsg.m.author;

    args.res.addEmbed(ds.EmbedBuilder()
      ..description = "Sent ${mod.it.get(it)} to <@${toPlayer.id}>"
      ..author = (ds.EmbedAuthorBuilder()
        ..name = author.username
        ..iconUrl = author.avatarURL()
      )
    );
  }
}

