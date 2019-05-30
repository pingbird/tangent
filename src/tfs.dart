import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'dart:typed_data';

abstract class TangentBD {
  FutureOr<List<int>> read(int start, int end);
  Future write(int start, List<int> data);
  FutureOr<int> get size;
}

class FileBD extends TangentBD {
  FileBD(this.f);
  RandomAccessFile f;

  FutureOr<List<int>> read(int start, int end) async {
    await f.setPosition(start);
    return await f.readSync(end - start);
  }

  Future write(int start, List<int> data) async {
    await f.setPosition(start);
    await f.writeFrom(data);
  }

  FutureOr<int> get size => f.length();
}

class BufferBD extends TangentBD {
  static const pageSize = 4096;
  List<Uint8List> pages;

  List<int> read(int start, int end) {
    var page = start ~/ pageSize;
    var offset = start - (page * pageSize);
    var bytes = end - start;
    var out = List<int>(bytes);
    var outOffset = 0;
    while (bytes > 0) {
      var n = min(bytes, pageSize - offset);
      bytes -= n;
      out.setRange(outOffset, outOffset + n, pages[page], offset);
      outOffset += n;
      offset = 0;
      page++;
    }
    return out;
  }

  Future write(int start, List<int> data) {
    while (start + data.length > pageSize * pages.length) {
      pages.add(Uint8List(pageSize));
    }

    var page = start ~/ pageSize;
    var offset = start - (page * pageSize);
    var dataOffset = 0;
    while (dataOffset < data.length) {
      var n = min(data.length - dataOffset, pageSize - offset);
      pages[page].setRange(offset, offset + n, data, dataOffset);
      dataOffset += n;
      offset = 0;
      page++;
    }
    return null;
  }

  int size = 0;
}

// atomic<T>:
//   T a
//   T b
//   u8 status:
//     0 | a active
//     1 | b active

class BDWriter {
  BDWriter(this.bd, this.offset);
  TangentBD bd;
  int offset;

  Future writeInt(int x) async {
    x = x.toUnsigned(32);
    await bd.write(offset, [
      (x >> 24) & 0xFF,
      (x >> 16) & 0xFF,
      (x >> 8) & 0xFF,
      x & 0xFF,
    ]);
    offset += 4;
  }

  Future<int> readInt() async {
    var d = await bd.read(offset, offset + 4);
    var o = d[0] << 24 | d[1] << 16 | d[2] << 8 | d[3];
    offset += 4;
    return o;
  }

  Future<List<int>> readBuf(int length) async {
    var o = await bd.read(offset, offset + length);
    offset += length;
    return o;
  }
}

class OpenNodeData {
  List<int> path;
  Map<int, OpenNodeData> children;
  int openCount = 0;
}

class TangentFS {
  FileBD device;
  TangentFS(this.device);

  static Future<TangentFS> openFile(String path) async =>
    TangentFS(FileBD(await File(path).open(mode: FileMode.write)));

  static const errNone = -1;

  BDWriter _wr(int offset) => BDWriter(device, offset);

  Future format() async {
    // TODO
  }

  Future<bool> exists(List<int> path) async {
    // TODO
  }

  Future<int> open(List<int> path) async {
    // TODO
  }

  Future<bool> spawn(int fd, int child) async {
    // TODO
  }

  Future close(int fd) async {
    // TODO
  }

  Future<int> length(int fd) async {
    // TODO
  }

  Future resize(int fd, int len) async {
    // TODO
  }

  Future<List<int>> read(int fd, int start, int end) async {
    // TODO
  }

  Future write(int fd, int start, Iterable<int> data) {
    // TODO
  }
}