import 'package:tangent/modules/rpg/data.dart';
import 'package:tangent/modules/rpg/base.dart';
import 'package:tangent/common.dart';

typedef ItemDesc ItemDescGetter(Item item, {int count});
typedef String _ToString();
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
  toString() => print();
}

class ItemContext {
  Map<String, ItemDescGetter> descs = {};

  void registerGetter(String id, ItemDescGetter getter) {
    descs[id] = getter;
  }

  void register(String id, {String name, String plural, String emoji, bool stacks, String stacksWith, String category, bool verbose, _ToString print, _Merger merger}) {
    name ??= id;
    descs[id] = (Item item, {int count}) {
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
        print: print ?? () {
          var emj = emoji == null ? "" : " ${
              emoji.startsWith("<") ? emoji : ":$emoji:"
          }";

          if (!verbose && emj != "") return "${fancyNum(count)} $emj";
          return (stacks ? fancyNum(count) + " " + (plural != null && (count > 1 || count < -1) ? plural : name) : name) + emj;
        },
        merger: merger ?? (a, b) {
          a.count += b.count;
          return true;
        },
      );
    };
  }

  ItemDesc get(Item i, {int count}) {
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
  ItemDelta(this.ctx);

  Set<Item> items = new Set();
  void addItem(Item x) {
    if (x.count == 0) return;
    var xInfo = ctx.get(x);
    if (xInfo.stacks) {
      for (var i in items.where((i) => i.id == x.id)) {
        var iInfo = ctx.get(i);
        if (iInfo.stacks && iInfo.stacksWith == xInfo.stacksWith && xInfo.merger(i, x)) {
          if (i.count == 0) {
            items.remove(i);
          }
          return;
        }
      }
    }
    if (x.count != 0) items.add(x);
  }

  void subtractItem(Item x) {
    if (x.count == 0) return;
    var xInfo = ctx.get(x);
    if (xInfo.stacks) {
      for (var i in items.where((i) => i.id == x.id)) {
        var iInfo = ctx.get(i);
        if (iInfo.stacks && iInfo.stacksWith == xInfo.stacksWith) {
          i.count -= x.count;
          if (i.count == 0) {
            items.remove(i);
          }
          return;
        }
      }
    }
    if (x.count != 0) items.add(new Item(x.id, -x.count, x.meta));
  }

  void addItems(ItemDelta d) {
    d.items.forEach(addItem);
  }

  void apply(Player e) {
    for (var x in items) {
      var xInfo = ctx.get(x);
      if (xInfo.stacks) {
        for (var i in e.items.where((i) => i.id == x.id)) {
          var iInfo = ctx.get(i);
          var ni = Item.fromJson(i.toJson());
          if (iInfo.stacks && iInfo.stacksWith == xInfo.stacksWith && xInfo.merger(ni, x)) {
            if (ni.count < 0 && ni.count < i.count) throw "Not enough ${iInfo.plural}.";
          }
        }
      }
    }

    for (var x in items) {
      var xInfo = ctx.get(x);
      bool added = false;
      if (xInfo.stacks) {
        for (var i in e.items.where((i) => i.id == x.id)) {
          var iInfo = ctx.get(i);
          if (iInfo.stacks && iInfo.stacksWith == xInfo.stacksWith && xInfo.merger(i, x)) {
            if (i.count == 0) {
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

  toString() => items.map((i) => (i.count > 0 ? "+" : "") + ctx.get(i).toString()).join(", ");
}