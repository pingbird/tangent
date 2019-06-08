import 'package:json_annotation/json_annotation.dart';
import 'base.dart';

@JsonSerializable() class RpgDB {
  Map<int, Player> players = {};
}

@JsonSerializable() class Item {
  Item.nil();
  Item(this.id, [this.count, this.meta]) {
    count ??= 1;
    meta ??= {};
  }

  String id;
  int count;
  Map<String, String> meta;
}

@JsonSerializable() class Entity {
  String id;
  double health;
  List<Item> items;
}

@JsonSerializable() class Player extends Entity {
  int level;
  Map<String, int> cooldowns;
  Map<String, String> meta;
  int ban;
  int lastMsg;
  double spam;
  int strike;
  String lastText;
}