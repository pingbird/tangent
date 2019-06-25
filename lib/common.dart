import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:mirrors' as mirrors;

import 'package:dartis/dartis.dart' as redis;
import 'package:tuple/tuple.dart';

abstract class BasicStringSink implements StreamSink<List<int>>, StringSink {
  void write(Object obj) {
    add(Utf8Codec().encode("$obj"));
  }

  void writeAll(Iterable objects, [String separator = ""]) {
    write(objects.join(separator));
  }

  void writeCharCode(int charCode) {
    add([charCode]);
  }

  void writeln([Object obj = ""]) {
    write("${obj}\n");
  }

  Future addStream(Stream<List<int>> stream) async {
    await stream.listen(add).asFuture();
    return null;
  }
}

const int _LF = 10;
const int _CR = 13;

class LimitedLineSplitter extends StreamTransformerBase<String, String> {
  final int lengthLimit;
  const LimitedLineSplitter(this.lengthLimit);

  static Iterable<String> split(String lines, [int start = 0, int end]) sync* {
    end = RangeError.checkValidRange(start, end, lines.length);
    var sliceStart = start;
    var char = 0;
    for (var i = start; i < end; i++) {
      var previousChar = char;
      char = lines.codeUnitAt(i);
      if (char != _CR) {
        if (char != _LF) continue;
        if (previousChar == _CR) {
          sliceStart = i + 1;
          continue;
        }
      }
      yield lines.substring(sliceStart, i);
      sliceStart = i + 1;
    }
    if (sliceStart < end) {
      yield lines.substring(sliceStart, end);
    }
  }

  List<String> convert(String data) {
    var lines = <String>[];
    var end = data.length;
    var sliceStart = 0;
    var char = 0;
    for (var i = 0; i < end; i++) {
      var previousChar = char;
      char = data.codeUnitAt(i);
      if (char != _CR) {
        if (char != _LF) continue;
        if (previousChar == _CR) {
          sliceStart = i + 1;
          continue;
        }
      }
      lines.add(data.substring(sliceStart, i));
      sliceStart = i + 1;
    }
    if (sliceStart < end) {
      lines.add(data.substring(sliceStart, end));
    }
    return lines;
  }

  StringConversionSink startChunkedConversion(Sink<String> sink) {
    return _LineSplitterSink(
        sink is StringConversionSink ? sink : StringConversionSink.from(sink),
        lengthLimit);
  }

  Stream<String> bind(Stream<String> stream) {
    return Stream<String>.eventTransformed(
        stream, (EventSink<String> sink) => _LineSplitterEventSink(sink, lengthLimit));
  }
}

class _LineSplitterSink extends StringConversionSinkBase {
  final int lengthLimit;
  final StringConversionSink _sink;

  String _carry;

  bool _skipLeadingLF = false;

  _LineSplitterSink(this._sink, this.lengthLimit);

  void addSlice(String chunk, int start, int end, bool isLast) {
    end = RangeError.checkValidRange(start, end, chunk.length);
    if (start >= end) {
      if (isLast) close();
      return;
    }

    if ((end - start) + (_carry?.length ?? 0) > lengthLimit) {
      throw Exception("Line length limit reached");
    }

    if (_carry != null) {
      assert(!_skipLeadingLF);
      chunk = _carry + chunk.substring(start, end);
      start = 0;
      end = chunk.length;
      _carry = null;
    } else if (_skipLeadingLF) {
      if (chunk.codeUnitAt(start) == _LF) {
        start += 1;
      }
      _skipLeadingLF = false;
    }
    _addLines(chunk, start, end);
    if (isLast) close();
  }

  void close() {
    if (_carry != null) {
      _sink.add(_carry);
      _carry = null;
    }
    _sink.close();
  }

  void _addLines(String lines, int start, int end) {
    var sliceStart = start;
    var char = 0;
    for (var i = start; i < end; i++) {
      var previousChar = char;
      char = lines.codeUnitAt(i);
      if (char != _CR) {
        if (char != _LF) continue;
        if (previousChar == _CR) {
          sliceStart = i + 1;
          continue;
        }
      }
      _sink.add(lines.substring(sliceStart, i));
      sliceStart = i + 1;
    }
    if (sliceStart < end) {
      _carry = lines.substring(sliceStart, end);
    } else {
      _skipLeadingLF = (char == _CR);
    }
  }
}

class _LineSplitterEventSink extends _LineSplitterSink
    implements EventSink<String> {
  final int lengthLimit;
  final EventSink<String> _eventSink;

  _LineSplitterEventSink(EventSink<String> eventSink, this.lengthLimit)
      : _eventSink = eventSink,
        super(StringConversionSink.from(eventSink), lengthLimit);

  void addError(Object o, [StackTrace stackTrace]) {
    _eventSink.addError(o, stackTrace);
  }
}

class ArgParse {
  ArgParse(this.raw, {bool parseFlags = true}) {
    Map<String, String> escapes = {
      "a": "\a",
      "b": "\b",
      "f": "\f",
      "n": "\n",
      "r": "\r",
      "t": "\t",
      "v": "\v",
    };

    String peek([int num = 1]) {
      if (num > raw.length) return "";
      return raw.substring(0, num);
    }

    String pop([int num = 1]) {
      var out = peek(num);
      raw = raw.substring(num);
      return out;
    }

    String readString() {
      while (peek() == " " || peek() == "\n") pop();
      var str = "";
      if (peek() == "\"") {
        pop();
        while (peek() != "\"" && raw.length > 0) {
          if (peek() == "\\") {
            pop();
            var idx = pop();
            var escape = escapes[idx];
            str += escape == null ? idx : escape;
          } else {
            str += pop();
          }
        }
        if (raw.length > 0) pop();
      } else {
        while (peek() != " " && peek() != "\n" && raw.length > 0) {
          str += pop();
        }
      }
      return str;
    }

    while (true) {
      while (peek() == " " || peek() == "\n") pop();
      if (raw.length == 0) break;
      if (parseFlags && peek() == "-") { // flag
        pop();
        var key = readString();
        while (peek() == " " || peek() == "\n") pop();
        var value = "true";
        if (peek() == "=") {
          pop();
          value = readString();
        }
        map[key] = value;
      } else {
        list.add(readString());
      }
    }
  }

  Map<String, String> map = new Map<String, String>();
  List<String> list = new List<String>();
  String raw = "";
}

String sizeToString(int bytes, [int frac = 1]) {
  var n = bytes.toDouble();
  if (n < 1024) {
    return "${n.toStringAsFixed(0)}B";
  }

  for (var u in [
    "KB", "MB", "GB", "TB", "EB", "ZB",
  ]) {
    n = n / 1024;
    if (n < 500) {
      return "${n.toStringAsFixed(frac)}$u";
    }
  }

  n / 1024;
  return "${n.toStringAsFixed(frac)}YB";
}

const _rt = const <String, double>{
  "millisecond": 0.001,
  "second": 1.0,
  "minute": 60.0,
  "hour": 3600.0,
  "day": 86400.0,
  "week": 604800.0,
  "month": 2629800.0,
};

const _wt = const <String, int>{
  "millisecond": 1000,
  "second": 60,
  "minute": 60,
  "hour": 24,
  "day": 7,
  "week": 7,
  "month": 12,
};

String toTime(num s) {
  if (s == double.infinity) return "never";
  if (s == double.negativeInfinity) return "forever ago";
  if (s == double.nan) return "unknown";

  var sr = "";
  if (s < 0) {
    sr = " ago";
    s = s.abs();
  }

  String c(String n) {
    var t = (s / _rt[n]).floor() % _wt[n];
    return "$t $n${t != 1 ? "s" : ""}";
  }

  if (s < 1) {
    return "${c("millisecond")}$sr";
  } else if (s < 60) {
    return "${c("second")}$sr";
  } else if (s < 3600) {
    if (s / 60 < 5 && (s % 60).floor() != 0) {
      return "${c("minute")} ${c("second")}$sr";
    }
    return "${c("minute")}$sr";
  } else if (s < 86400) {
    return "${c("hour")} ${c("minute")}$sr";
  } else if (s < 86400) {
    return "${c("hour")} ${c("minute")}$sr";
  } else if (s < 604800) {
    return "${c("day")} ${c("hour")}$sr";
  } else if (s < 2629800) {
    return "${c("week")} ${c("day")}$sr";
  } else {
    return "${c("month")}$sr";
  }
}

String fancyBig(BigInt n) {
  var ndn = n.abs().toString();
  return (n < BigInt.zero ? "-" : "") + ndn.split("").reversed.join()
    .replaceAllMapped(new RegExp(r"..."), (m) => m.group(0) + ",")
    .split("").reversed.join().replaceFirst(new RegExp("^,"), "");
}

String fancyNum(num n) {
  var nnn = n.abs().toString();
  var ndn = n.abs().floor().toString();
  var o = (n < 0 ? "-" : "") + ndn.split("").reversed.join()
    .replaceAllMapped(new RegExp(r"..."), (m) => m.group(0) + ",")
    .split("").reversed.join().replaceFirst(new RegExp("^,"), "") + nnn.split("").skipWhile((c) => c != ".").join();
  return o.replaceAll(new RegExp(r"\.0$"), "");
}

Stream<T> redisScanList<T>(redis.Client cl, dynamic pattern, int count) async* {
  var cursor = 0;
  while (true) {
    var res = await cl.asCommands<T, dynamic>().scan(cursor, pattern: pattern);
    yield* Stream.fromIterable(res.keys);
    cursor = res.cursor;
    if (cursor == 0) break;
  }
}

Stream<T> redisScanHash<T>(redis.Client cl, dynamic pattern, int count) async* {
  var cursor = 0;
  while (true) {
    var res = await cl.asCommands<T, dynamic>().scan(cursor, pattern: pattern);
    yield* Stream.fromIterable(res.keys);
    cursor = res.cursor;
    if (cursor == 0) break;
  }
}

typedef T _RunTimeFunc<T, X>(X x);

class _RunTimeObj<T, X> {
  _RunTimeObj(this.x, this.func, this.sp, this.spErr);
  X x;
  _RunTimeFunc<T, X> func;
  SendPort sp;
  SendPort spErr;
}

void _runTimeIso(dynamic ob) async {
  _RunTimeObj obj = ob;
  try {
    obj.sp.send(await ob.func(obj.x));
  } catch (e, bt) {
    obj.spErr.send(Tuple2(e.toString(), bt.toString()));
  }
  print("potato");
}

Future<T> runTimeLimit<T, X>(Future<T> func(X x), X message, int ms) async {
  print("runTimeLimit");
  var rp = ReceivePort();
  var rpErr = ReceivePort();
  var iso = await Isolate.spawn(_runTimeIso, _RunTimeObj(message, func, rp.sendPort, rpErr.sendPort));
  print("started iso");

  var o = await Future.any([
    rp.first,
    Future.delayed(Duration(milliseconds: ms)),
    rpErr.first.then((d) => Future.error(d.item1, StackTrace.fromString(d.item2))),
  ]);

  print("done waiting $o");

  iso.kill();
  return o;
}

String toHex(List<int> bytes) {
  var out = new StringBuffer();
  for (int i = 0; i<bytes.length; i++) {
    var part = bytes[i];
    out.write(part.toRadixString(16).padLeft(2, "0"));
  }
  return out.toString();
}


int levenshtein(String s, String t, {bool caseSensitive = true}) {
  if (!caseSensitive) {
    s = s.toLowerCase();
    t = t.toLowerCase();
  }
  if (s == t)
    return 0;
  if (s.isEmpty)
    return t.length;
  if (t.isEmpty)
    return s.length;

  List<int> v0 = new List<int>.filled(t.length + 1, 0);
  List<int> v1 = new List<int>.filled(t.length + 1, 0);

  for (int i = 0; i < t.length + 1; i < i++)
    v0[i] = i;

  for (int i = 0; i < s.length; i++) {
    v1[0] = i + 1;

    for (int j = 0; j < t.length; j++) {
      int cost = (s[i] == t[j]) ? 0 : 1;
      v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
    }

    for (int j = 0; j < t.length + 1; j++) {
      v0[j] = v1[j];
    }
  }

  return v1[t.length];
}

Map<K, V> mapFromIterable<T, K, V>(List<T> list, {K key(T element), V value(T element)}) =>
  Map<K, V>.fromIterable(list,
    key: key == null ? null : (e) => key(e as T),
    value: value == null ? null : (e) => value(e as T),
  );
