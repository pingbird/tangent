import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nyxx/nyxx.dart';

import '../main.dart';

class GitModule extends TangentModule {
  WebSocket ws;

  var events = StreamController();

  Future reconnect() async {
    if (!loaded) return;
    ws = await WebSocket.connect("wss://me.tst.sh/tangent-webhook/ws");
    print("Webhook connected");
    ws.add(jsonEncode({"secret": await File("tokens/webhook_collector.txt").readAsString()}));
    ws.listen((dataText) {
      print("got ${dataText}");
      if (dataText is String) {
        var data = jsonDecode(dataText) as List;
        print("adding");
        for (var d in data) events.add(d);
      }
    }, onDone: () {
      reconnect();
    }, cancelOnError: true);
  }

  Future init() async {
    print("Connecting to webhook collector...");
    await reconnect();
  }

  Future dispose() async {
    try {
      await ws.close();
    } catch (e, bt) {
      stderr.writeln(e);
      stderr.writeln(bt);
    }
  }

  onReady() async {
    TextChannel ch = await nyxx.getChannel(Snowflake("583480062993629194"));
    await for (var ev in events.stream) {
      try {
        print(JsonEncoder.withIndent("  ").convert(ev));
        if (ev["event-type"] == "push") {
          List commits = ev["commits"];
          var branch = (ev["ref"] as String).substring(11);
          var messages = commits.map((c) {
            var id = c["id"] as String;
            return "[`[${id.substring(0, 8)}]`](${c["url"]}) ${c["message"]}";
          }).toList();
          var lmsg = [];
          var nAdded = commits.expand((e) => e["added"]).length;
          if (nAdded > 0) lmsg.add("$nAdded file${nAdded == 1 ? "" : "s"} added");
          var nRemoved = commits.expand((e) => e["removed"]).length;
          if (nRemoved > 0) lmsg.add("$nRemoved file${nRemoved == 1 ? "" : "s"} removed");
          var nModified = commits.expand((e) => e["modified"]).length;
          if (nModified > 0) lmsg.add("$nModified file${nModified == 1 ? "" : "s"} modified");
          if (lmsg.isNotEmpty) messages.add("");
          messages.add(lmsg.join("\n"));

          await ch.send(
            embed: EmbedBuilder()
              ..color = DiscordColor.fromInt(0x0086ce)
              ..author = (EmbedAuthorBuilder()
                ..name = "${ev["repository"]["name"]}:$branch +${commits.length} New commit${commits.length > 1 ? "s" : ""}"
                ..url = ev["repository"]["html_url"]
              )
              ..description = messages.join("\n")
              ..footer = (EmbedFooterBuilder()
                ..text = ev["pusher"]["name"]
                ..iconUrl = ev["sender"]["avatar_url"]
              )
              ..thumbnailUrl = "https://github.githubassets.com/images/modules/logos_page/Octocat.png"
              ..timestamp = DateTime.parse(ev["head_commit"]["timestamp"])
          );
        } else return;
        await Future.delayed(Duration(seconds: 5));
      } catch (e, bt) {
        stderr.writeln(e);
        stderr.writeln(bt);
      }
    }
  }
}