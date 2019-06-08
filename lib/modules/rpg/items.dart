import 'package:tangent/modules/rpg/data.dart';
import 'package:tangent/modules/rpg/base.dart';
import 'package:tangent/common.dart';

typedef ItemInfo ItemInfoGetter(Item item);
typedef String _ToString();
typedef bool _Merger(Item a, Item b);

class ItemInfo {
  ItemInfo({this.name, this.plural, this.emoji, this.stacksWith, this.category, this.stacks, this.print, this.merger});
  String name;
  String plural;
  String emoji;
  String stacksWith;
  String category;
  _ToString print;
  _Merger merger;
  bool stacks = true;
  toString() => print();
}

class ItemContext {
  Map<String, ItemInfoGetter> itemInfo = {};

  void registerGetter(String id, ItemInfoGetter getter) {
    itemInfo[id] = getter;
  }

  void register(String id, {String name, String plural, String emoji, bool stacks, String stacksWith, String category, _ToString print, _Merger merger}) {
    name ??= id;
    itemInfo[id] = (Item item) {
      return new ItemInfo(
        name: name,
        plural: plural,
        emoji: emoji,
        stacksWith: stacksWith,
        category: category,
        stacks: stacks ?? true,
        print: print ?? () {
          var emj = emoji == null ? "" : " ${
              emoji.startsWith("<") ? emoji : ":$emoji:"
          }";
          return (stacks ? fancyNum(item.count.toDouble()) + " " + (plural != null && (item.count > 1 || item.count < -1) ? plural : name) : name) + emj;
        },
        merger: merger ?? (a, b) {
          a.count += b.count;
          return true;
        },
      );
    };
  }

  ItemInfo get(Item i) {
    if (!itemInfo.containsKey(i.id)) register(
      i.id,
      name: "\\_${i.id}\\_",
      emoji: "x",
      stacks: true,
    );

    return itemInfo[i.id](i);
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

  toString() => items.map((i) => (i.count > 0 ? "+" : "") + i.toString()).join(", ");
}