import 'dart:convert';
import 'dart:io';

import 'package:tangent/base.dart';
import 'package:tangent/common.dart';
import 'package:tangent/modules/commands.dart';
import 'package:tangent/modules/rpg/data.dart';
import 'package:tangent/modules/rpg/base.dart';
import 'package:tangent/modules/rpg/items.dart';

import 'package:nyxx/nyxx.dart' as ds;

class ExchangePlugin extends RpgPlugin {
  String token;

  Future init() async {
    mod.it.register("dollar", plural: "dollars");
    mod.it.register("yen");
    mod.it.register("euro", plural: "euros");
    mod.it.register("pound", plural: "pounds");

    token = (await File("tokens/fixer.txt").readAsString()).trim();

    exchangeUpdateTask();
  }

  void exchangeUpdateTask() async {
    while (true) {
      var dt = mod.db.exchange.nextUpdate - DateTime.now().millisecondsSinceEpoch;
      if (dt > 0) await Future.delayed(Duration(milliseconds: dt));

      try {
        var req = await HttpClient().getUrl(Uri.parse("http://data.fixer.io/api/latest?access_key=$token"));
        var data = await Utf8Codec().decodeStream(await req.close());
        print("wheee $data");
        mod.db.exchange.rates = (jsonDecode(data)["rates"] as Map).cast<String, num>();
      } catch (e, bt) {
        stderr.writeln("/// Exchange Error ///");
        stderr.writeln(e);
        stderr.writeln(bt);
      }

      var time = DateTime.now();
      var next = DateTime(time.year, time.month, time.day, time.hour + 1);

      mod.db.exchange.nextUpdate = next.millisecondsSinceEpoch;
      await mod.db.exchange.save();
    }
  }

  double convert(double value, String from, String to) =>
    value * (mod.db.exchange.rates[to] / mod.db.exchange.rates[from]);

  static const currencies = {
    "JPY": "yen",
    "EUR": "euro",
    "GBP": "pound",
    "USD": "dollar",
  };

  static const currencyCodes = {
    "yen": "JPY",
    "euro": "EUR",
    "pound": "GBP",
    "dollar": "USD",
  };

  @RpgCommand() rates(RpgArgs args) {
    return "\n" + [
      "1 :yen: Yen = ${convert(1, "JPY", "USD").toStringAsFixed(2)} :dollar: Dollars",
      "1 :euro: Euro = ${convert(1, "EUR", "USD").toStringAsFixed(2)} :dollar: Dollars",
      "1 :pound: Pound = ${convert(1, "GBP", "USD").toStringAsFixed(2)} :dollar: Dollars",
    ].join("\n");
  }

  String queryCurrencyName(String query) => mod.findQuery(query, [
    ...currencies.entries,
    ...currencies.entries.map((e) => MapEntry(e.key, e.key)),
  ], (e) => e.item2)?.key;

  @RpgCommand() listen(RpgArgs args) {
    const usage = "Usage: exchange <amount> <from> <to>";
    if (args.list.length != 3) return usage;
    var fromAc = queryCurrencyName(args.list[1]);
    var toAc = queryCurrencyName(args.list[2]);
    if (fromAc == null) return "Unknown currency: $fromAc";
    if (toAc == null) return "Unknown currency: $toAc";

    var stored = args.player.getItemCount(currencies[fromAc]);
    if (stored == 0) return "You do not have any ${mod.it.get(Item(currencies[fromAc], 2)).toString(amount: false)}.";

    int amt;
    if (args.list[0] == "*" || args.list[0] == "all") {
      amt = stored;
    } else {
      amt = int.tryParse(args.list[0]);
    }

    if (amt == null || amt < 1) return "Amount must be an integer greater than zero.";
  }
}