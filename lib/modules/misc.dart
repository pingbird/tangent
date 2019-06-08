import 'dart:math';

import 'package:nyxx/nyxx.dart' as ds;

import 'package:tangent/base.dart';
import 'package:tangent/common.dart';
import 'package:tangent/modules/commands.dart';

class MiscModule extends TangentModule {
  @Command() echo(CommandArgs args) {
    args.res.writeln(args.text);
  }

  @Command(admin: true) purge(CommandArgs args) async {
    var count = args.expectInt();
    args.expectNone();
    var chan = args.msg.channel;

    ds.Snowflake earliest = args.msg.m.id;
    while (count > 0) {
      var n = min(count, 99);
      count -= n;
      var msgs = await chan.getMessages(before: earliest, limit: n).toList();
      print(msgs.length);
      if (count == 0) msgs.add(args.msg.m);
      await chan.bulkRemoveMessages(msgs);
      earliest = msgs.first.id;
    }
  }
}