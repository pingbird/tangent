import 'dart:convert';
import 'dart:io';

import 'package:tangent/base.dart';
import 'package:tangent/common.dart';
import 'package:tangent/modules/commands.dart';
import 'package:dartis/dartis.dart' as redis;
import 'package:llama/expr.dart';
import 'package:llama/llama.dart';
import 'package:llama/solvers/trash.dart';

Future<Expr> _doParse(String str) => Parser().parse("", str);
Future<Expr> parseSafe(String str) => runTimeLimit(_doParse, str, 5000);

Future<Expr> _doReduce(Expr e) async => (TrashSolver(e..bind())..solve()).expr;
Future<Expr> reduceSafe(Expr e) => runTimeLimit(_doReduce, e, 5000);

class LambdaModule extends TangentModule {
  init() async {
    try {
      var f = new File("db/lambda.json");
      if (await f.exists()) {
        // var m = (jsonDecode(await f.readAsString()) as Map).cast<String, String>();
        // g = new Map.fromIterable(m.keys, value: (e) => Parser().parse("", m[e]));
      }
    } catch (e, bt) {
      stderr.writeln("[lambda] Failed to load globals!");
      stderr.writeln(e);
      stderr.writeln(bt);
    }
  }

  @Command() l(CommandArgs args) async {
    var e = await parseSafe("~\\\"stdlib.lf\"\n${args.text}");
    if (e == null) throw "Parse timed out";
    var o = await reduceSafe(e);
    if (o == null) throw "Reduction timed out";
    args.res.writeln(o.toString());
  }
}
