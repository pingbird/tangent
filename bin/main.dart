import 'package:tangent/base.dart';

void main(List<String> args) async {
  if (args.isEmpty) throw "Instance name expected";
  var t = TangentInstance();
  t.start(args.first);
}