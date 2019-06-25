import 'dart:math';

import 'package:tangent/modules/rpg/data.dart';
import 'package:tangent/modules/rpg/base.dart';
import 'package:tangent/common.dart';
import 'package:tuple/tuple.dart';

typedef ItemDesc ItemDescGen(Item item, {BigInt count});
typedef String _ToString({bool amount});
typedef bool _Merger(Item a, Item b);

class ItemDesc {
  ItemDesc({this.name, this.plural, this.emoji, this.stacksWith, this.category, this.verbose, this.stacks, this.print, this.merger});
  String name;
  String plural;
  String emoji;
  String stacksWith;
  String category;
  bool verbose;
  _ToString print;
  _Merger merger;
  bool stacks = true;
  toString({bool amount = true}) => print(amount: amount);
}

class ItemContext {
  Map<String, ItemDescGen> descs = {};

  void registerGetter(String id, ItemDescGen getter) {
    descs[id] = getter;
  }

  void register(String id, {String name, String plural, String emoji, bool stacks, String stacksWith, String category, bool verbose, _ToString print, _Merger merger}) {
    name ??= id;
    descs[id] = (Item item, {BigInt count}) {
      count ??= item.count;
      stacks ??= true;
      verbose ??= false;
      return new ItemDesc(
        name: name,
        plural: plural,
        emoji: emoji,
        stacksWith: stacksWith,
        category: category,
        stacks: stacks,
        verbose: verbose,
        print: print ?? ({bool amount}) {
          var emj = emoji == null ? "" : " ${
              emoji.startsWith("<") ? emoji : ":$emoji:"
          }";

          if (!verbose && emj != "") return "${fancyBig(count)} $emj";

          var nstr = plural != null && (count > BigInt.one || count < -BigInt.one) ? plural : name;
          if (!stacks || !amount) {
            return "$nstr$emj";
          } else {
            return "${fancyBig(count)} $nstr$emj";
          }
        },
        merger: merger ?? (a, b) {
          a.count += b.count;
          return true;
        },
      );
    };
  }

  ItemDesc get(Item i, {BigInt count}) {
    if (!descs.containsKey(i.id)) register(
      i.id,
      name: "\\_${i.id}\\_",
      stacks: true,
    );

    return descs[i.id](i, count: count);
  }
}

class ItemDelta {
  ItemContext ctx;
  Set<Item> items;

  ItemDelta(this.ctx, {this.items}) {
    items ??= Set();
  }

  bool get isEmpty => !items.any((i) => i.count != BigInt.zero);
  bool get isNotEmpty => items.any((i) => i.count != BigInt.zero);

  void addItem(Item x) {
    if (x.count == BigInt.zero) return;
    var xInfo = ctx.get(x);
    if (xInfo.stacks) {
      for (var i in items.where((i) => i.id == x.id)) {
        var iInfo = ctx.get(i);
        if (iInfo.stacks && iInfo.stacksWith == xInfo.stacksWith && xInfo.merger(i, x)) {
          if (i.count == BigInt.zero) {
            items.remove(i);
          }
          return;
        }
      }
    }
    if (x.count != BigInt.zero) items.add(x);
  }

  void addItems(Iterable<Item> items) => items.forEach(addItem);

  void removeItem(Item x) {
    if (x.count == BigInt.zero) return;
    var xInfo = ctx.get(x);
    if (xInfo.stacks) {
      for (var i in items.where((i) => i.id == x.id)) {
        var iInfo = ctx.get(i);
        if (iInfo.stacks && iInfo.stacksWith == xInfo.stacksWith) {
          i.count -= x.count;
          if (i.count == BigInt.zero) {
            items.remove(i);
          }
          return;
        }
      }
    }
    if (x.count != BigInt.zero) items.add(new Item(x.id, -x.count, x.meta));
  }

  void removeItems(Iterable<Item> items) => items.forEach(removeItem);

  void addItemDt(ItemDelta d) {
    d.items.forEach(addItem);
  }

  Tuple2<Item, Item> checkApply(Player e) {
    for (var x in items) {
      var xInfo = ctx.get(x);
      if (xInfo.stacks) {
        bool found = false;
        var ql = e.items.where((i) => i.id == x.id);
        for (var i in ql) {
          var iInfo = ctx.get(i);
          var ni = i.copy();
          if (iInfo.stacks && iInfo.stacksWith == xInfo.stacksWith && xInfo.merger(ni, x)) {
            if (ni.count < BigInt.zero && ni.count < i.count) return Tuple2(i, x);
            found = true;
            break;
          }
        }
        if (!found && x.count < BigInt.zero) return Tuple2(Item.int(x.id), x);
      }
    }
    return null;
  }

  void apply(Player e) {
    for (var x in items) {
      var xInfo = ctx.get(x);
      bool added = false;
      if (xInfo.stacks) {
        for (var i in e.items.where((i) => i.id == x.id)) {
          var iInfo = ctx.get(i);
          if (iInfo.stacks && iInfo.stacksWith == xInfo.stacksWith && xInfo.merger(i, x)) {
            if (i.count == BigInt.zero) {
              e.items.remove(i);
            }
            added = true;
            break;
          }
        }
      }
      if (!added) e.items.add(x);
    }
    e.save();
  }

  ItemDelta operator-() => ItemDelta(ctx, items: items.map((i) => i.copy(count: -i.count)).toSet());

  toString() => items.map((i) => (i.count > BigInt.zero ? "+" : "") + ctx.get(i).toString()).join(", ");
}

typedef Iterable<Item> ItGen();

ItGen itGenAll(Iterable<ItGen> gens) => () =>
  gens.map((g) => g()).expand((e) => e);

ItGen itGenDist(Map<ItGen, double> gens) => () {
  var field = <Tuple2<double, ItGen>>[];

  var total = 0.0;
  for (var k in gens.keys) {
    total += gens[k];
    field.add(Tuple2(total, k));
  }

  var n = Random().nextDouble() * total;
  for (int i = 0;; i++) {
    if (n > field[i].item1) continue;
    return field[i].item2();
  }
};

typedef double ItCurve(double x);

ItCurve expCurve(double e, [double o = 0]) => (double d) => pow(d + o, e);
ItCurve invExpCurve(double e, [double o = 0]) => (double d) => 1 - pow(d + o, e);

ItGen itGenSingle(String id, {int start, int end, ItCurve curve, Map<String, String> meta}) => () {
  start ??= 1;
  end ??= start;
  int count;

  if (start == end) {
    count = start;
  } else {
    var n = Random().nextDouble();
    if (curve != null) n = max(0, min(1, curve(n)));
    count = ((n * (end - start)) + start).round();
  }

  return [Item.int(id, count, meta)];
};

class FarmRecipe {
  Item input;
  double growTime;
  ItGen output;
}

class RefineRecipe {
  RefineRecipe(this.minTime, this.maxTime, this.output);
  double minTime;
  double maxTime;
  ItGen output;
}

class RecipeRegistry {
  Map<String, Tuple2<List<Item>, List<Item>>> craft = {};
  Map<String, Tuple2<Item, ItGen>> crush = {};
  Map<String, RefineRecipe> refine = {};
}

T takeRandom<T>(Iterable<T> l) => l.elementAt(Random().nextInt(l.length));
T takeWeighted<T>(Map<T, double> m) {
  var field = <Tuple2<double, T>>[];

  var total = 0.0;
  for (var k in m.keys) {
    total += m[k];
    field.add(Tuple2(total, k));
  }

  var n = Random().nextDouble() * total;
  for (int i = 0;; i++) {
    if (n > field[i].item1) continue;
    return field[i].item2;
  }
}