// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ExchangeData _$ExchangeDataFromJson(Map<String, dynamic> json) {
  return ExchangeData()
    ..nextUpdate = json['nextUpdate'] as int
    ..rates = (json['rates'] as Map<String, dynamic>)?.map(
      (k, e) => MapEntry(k, e as num),
    );
}

Map<String, dynamic> _$ExchangeDataToJson(ExchangeData instance) =>
    <String, dynamic>{
      'nextUpdate': instance.nextUpdate,
      'rates': instance.rates
    };

Item _$ItemFromJson(Map<String, dynamic> json) {
  return Item(
      json['id'] as String,
      json['count'] == null ? null : BigInt.parse(json['count'] as String),
      (json['meta'] as Map<String, dynamic>)?.map(
        (k, e) => MapEntry(k, e as String),
      ));
}

Map<String, dynamic> _$ItemToJson(Item instance) => <String, dynamic>{
      'id': instance.id,
      'count': instance.count?.toString(),
      'meta': instance.meta
    };

RefineProgress _$RefineProgressFromJson(Map<String, dynamic> json) {
  return RefineProgress()
    ..time = json['time'] as int
    ..items = (json['items'] as List)
        ?.map(
            (e) => e == null ? null : Item.fromJson(e as Map<String, dynamic>))
        ?.toList();
}

Map<String, dynamic> _$RefineProgressToJson(RefineProgress instance) =>
    <String, dynamic>{'time': instance.time, 'items': instance.items};

Player _$PlayerFromJson(Map<String, dynamic> json) {
  return Player()
    ..level = json['level'] as int
    ..items = (json['items'] as List)
        ?.map(
            (e) => e == null ? null : Item.fromJson(e as Map<String, dynamic>))
        ?.toList()
    ..cooldowns = (json['cooldowns'] as Map<String, dynamic>)?.map(
      (k, e) => MapEntry(k, e as int),
    )
    ..meta = (json['meta'] as Map<String, dynamic>)?.map(
      (k, e) => MapEntry(k, e as String),
    )
    ..ban = json['ban'] as int
    ..lastMsgTime = json['lastMsgTime'] as int
    ..lastMsgText = json['lastMsgText'] as String
    ..spam = (json['spam'] as num)?.toDouble()
    ..strike = json['strike'] as int
    ..refineProgress = json['refineProgress'] == null
        ? null
        : RefineProgress.fromJson(
            json['refineProgress'] as Map<String, dynamic>);
}

Map<String, dynamic> _$PlayerToJson(Player instance) => <String, dynamic>{
      'level': instance.level,
      'items': instance.items,
      'cooldowns': instance.cooldowns,
      'meta': instance.meta,
      'ban': instance.ban,
      'lastMsgTime': instance.lastMsgTime,
      'lastMsgText': instance.lastMsgText,
      'spam': instance.spam,
      'strike': instance.strike,
      'refineProgress': instance.refineProgress
    };
