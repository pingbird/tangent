class StructDef { const StructDef(); }

abstract class Struct {
  RootStruct rootStruct;
  List<int> serialize();
  void bind(RootStruct r);
}

abstract class RootStruct extends Struct {
  bool dirty = true;
  RootStruct get rootStruct => this;
}