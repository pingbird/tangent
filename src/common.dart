import 'dart:async';
import 'dart:convert';

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

  addError(Object error, [StackTrace stackTrace]) {
    throw error;
  }

  Future addStream(Stream<List<int>> stream) {
    stream.listen(add);
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
