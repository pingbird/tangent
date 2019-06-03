import '../main.dart';
import 'commands.dart';

class GlobalState {
  Map<String, Exp> vars = {};
}

class BindState {
  int uid = 0;
  GlobalState g;
}

abstract class Exp {
  String toString([Exp parent, bool first]);
  String toVerbose();

  Exp reduce() {
    var x = this;
    if (x is Lambda) {
      x.body = x.body.reduce();
    } else if (x is Apply) {
      var l = x.lambda.reduce();
      x.lambda = l;
      if (l is Lambda) {
        return (new Sub(l.body, l.name, x.param.reduce())..id = l.id ..bindState = bindState).reduce();
      } else {
        x.param = x.param.reduce();
      }
    } else if (x is Sub) {
      Exp step(Exp e) {
        if (e is Lambda) {
          if (e.name == x.name && e.id == x.id) return e;
          e.body = step(e.body);
        } else if (e is Apply) {
          e.lambda = step(e.lambda);
          e.param = step(e.param);
        } else if (e is Sub) {
          if (e.name == x.name && e.id == x.id) return e;
          e.body = step(e.body);
          e.to = step(e.to);
        } else if (e is Ref) {
          if (e.name == x.name && e.bound == x.id) {
            return x.to.copy();
          }
        }
        return e;
      }
      return step(x.body).reduce();
    } else if (x is Ref) {
      if (x.extern && bindState.g.vars.containsKey(x.name)) {
        return bindState.g.vars[x.name].copy(bindState).reduce();
      }
    }
    return x;
  }

  void bind() {
    bindState = bindState ?? new BindState();
    Map<String, List<int>> binds = {};
    void bn(Exp x) {
      x.bindState = bindState;
      if (x is Lambda) {
        x.id = bindState.uid++;
        binds.putIfAbsent(x.name, () => []).add(x.id);
        bn(x.body);
        binds[x.name].removeLast();
        if (binds[x.name].isEmpty) binds.remove(x.name);
      } else if (x is Apply) {
        bn(x.lambda);
        bn(x.param);
      } else if (x is Sub) {
        bn(x.to);
        x.id = bindState.uid++;
        binds.putIfAbsent(x.name, () => []).add(x.id);
        bn(x.body);
        binds[x.name].removeLast();
        if (binds[x.name].isEmpty) binds.remove(x.name);
      } else if (x is Ref) {
        if (binds.containsKey(x.name)) {
          x.bound = binds[x.name].last;
        } else {
          x.extern = true;
        }
      } else throw "Unknown type";
    }
    bn(this);
  }

  void applyCol() {
    bool used(Exp x, int id) {
      if (x is Lambda) {
        if (x.id == id) return false;
        return used(x.body, id);
      } else if (x is Apply) {
        return used(x.lambda, id) || used(x.param, id);
      } else if (x is Sub) {
        return used(x.body, id) || used(x.to, id);
      } else if (x is Ref) {
        return x.bound == id;
      } else throw "Unknown type";
    }

    bool collides(Exp x, int id, String name) {
      if (x is Lambda) {
        if (x.id == id) return false;
        if (x.name == name && used(x.body, id)) return true;
        return collides(x.body, id, name);
      } else if (x is Apply) {
        return collides(x.lambda, id, name) || collides(x.param, id, name);
      } else if (x is Sub) {
        return collides(x.body, id, name) || collides(x.to, id, name);
      } else if (x is Ref) {
        return x.name == name && x.bound != id;
      } else throw "Unknown type";
    }

    List<Binder> s = [];

    void cl(Exp x) {
      if (x is Lambda) {
        if (!collides(x.body, x.id, x.name) || !used(x.body, x.id)) return cl(x.body);
        var a = s.where((e) => e.name == x.name);
        x.col = a.isEmpty ? 1 : a.last.col + 1;
        s.add(x);
        cl(x.body);
        s.removeLast();
      } else if (x is Apply) {
        cl(x.lambda);
        cl(x.param);
      } else if (x is Sub) {
        if (!collides(x, x.id, x.name)) return cl(x.body);
        var a = s.where((e) => e.name == x.name);
        x.col = a.isEmpty ? 1 : a.last.col + 1;
        s.add(x);
        cl(x.body);
        s.removeLast();
      } else if (x is Ref) {
        if (x.extern) return null;
        var a = s.where((e) => e.id == x.bound);
        if (a.isEmpty) return null;
        x.col = a.last.col;
      } else throw "Unknown type";
    }
    cl(this);
  }

  Exp copy([BindState bs]) {
    bs ??= bindState;
    Map<int, Ref> rebindRefs = {};
    Exp cp(Exp x) {
      if (x is Lambda) {
        Ref r = rebindRefs.putIfAbsent(x.id, () => new Ref(x.name)..bound = bs.uid++ ..bindState = bs);
        return new Lambda(x.name, cp(x.body))..id = r.bound ..bindState = bs;
      } else if (x is Apply) {
        return new Apply(cp(x.lambda), cp(x.param))..bindState = bs;
      } else if (x is Sub) {
        Ref r = rebindRefs.putIfAbsent(x.id, () => new Ref(x.name)..bound = bs.uid++ ..bindState = bs);
        return new Sub(cp(x.body), x.name, cp(x.to))..id = r.bound ..bindState = bs;
      } else if (x is Ref) {
        if (rebindRefs.containsKey(x.bound)) {
          return rebindRefs[x.bound];
        } else {
          return new Ref(x.name)..bound = x.bound ..bindState = bs;
        }
      } else throw "Unknown type";
    }
    return cp(this);
  }

  static Exp fromList(List<Exp> l) {
    if (l.length == 0) {
      return null;
    } else {
      var o = l[0];
      for (int i = 1; i < l.length; i++) {
        o = new Apply(o, l[i]);
      }
      return o;
    }
  }

  BindState bindState;
}

abstract class Binder {
  String name;
  int id;
  int col;
}

class Lambda extends Exp implements Binder {
  Lambda(this.name, this.body);
  String name;
  int id = 0;
  int col = 0;
  Exp body;

  String toString([Exp parent, bool first]) {
    int n = toNumber();
    if (n != null) return n.toString();
    if (parent == null || parent is Lambda) {
      var ob = this;
      String o = "";
      while (ob is Lambda) {
        o = "$o${o.length == 0 ? "" : " "}${ob.name}${col > 0 ? toSubscript(col) : ""}";
        ob = ob.body;
      }
      return "λ$o.${ob.toString(this)}";
    }
    return "($this)";
  }

  String toVerbose() => "(^$name${toSubscript(id)}.${body.toVerbose()})";

  int toNumber() {
    if (body is! Lambda) return null;
    var vn = (body as Lambda).name;
    if (vn == name) return null;
    if ((body as Lambda).body is Ref && ((body as Lambda).body as Ref).bound == (body as Lambda).id) return 0;
    if ((body as Lambda).body is! Apply) return null;
    int i = 1;
    Apply ca = (body as Lambda).body;
    while (true) {
      if (ca.lambda is! Ref) return null;
      if ((ca.lambda as Ref).bound != this.id) return null;
      if (ca.param is Ref && (ca.param as Ref).bound == (body as Lambda).id) break;
      if (ca.param is! Apply) return null;
      if (ca.lambda is! Ref) return null;
      i++;
      ca = ca.param;
    }
    return i;
  }
}

class Apply extends Exp {
  Apply(this.lambda, this.param);
  Exp lambda;
  Exp param;

  String toVerbose() => "(${lambda.toVerbose()} ${param.toVerbose()})";

  String toString([Exp parent, bool first = false]) {
    if (parent == null || parent is Lambda || first) {
      return "${lambda.toString(this, true)} ${param is Lambda && parent is! Apply ? param : param.toString(this)}";
    }
    return "(${lambda.toString(this, true)} ${parent is Lambda ? param : param.toString(this)})";
  }
}

class Sub extends Exp implements Binder {
  Sub(this.body, this.name, this.to);
  Exp body;
  String name;
  Exp to;
  int id = 0;
  int col = 0;
  String toString([Exp parent, bool first]) => "${body.toString(this)}[$name⇒${to}]";
  String toVerbose() => "(${body.toVerbose()}[$name${toSubscript(id)}=${to.toVerbose()}])";
}

String subscriptPattern = r"[₀₁₂₃₄₅₆₇₈₉]";
const subscript = const {"0":"₀", "1":"₁", "2":"₂", "3":"₃", "4":"₄", "5":"₅", "6":"₆", "7":"₇", "8":"₈", "9":"₉"};
String toSubscript(int i) => i.toString().split(r".").map((x) => subscript[x]).join();
const subscript2 = const {"₀":"0", "₁":"1", "₂":"2", "₃":"3", "₄":"4", "₅":"5", "₆":"6", "₇":"7", "₈":"8", "₉":"9"};
int fromSubscript(String s) => int.parse(s.split(r".").map((x) => subscript2[x]).join());

class Ref extends Exp {
  Ref(this.name);
  String name;
  int bound = 0;
  int col = 0;
  bool extern = false;
  String toString([Exp parent, bool first]) => extern ? "*$name*" : col > 0 ? name + toSubscript(col) : name;
  String toVerbose() => extern ? "ₑ$name" : "$name${toSubscript(bound)}";
}

class Parser {
  Parser(this.inp, this.verbose);
  String inp;
  bool verbose = false;

  String readPattern(String pattern) {
    var res = new RegExp(pattern).matchAsPrefix(inp);
    if (res == null) return null;
    inp = inp.substring(res.group(0).length);
    return res.group(0);
  }

  String readWord() => readPattern(r"[A-Za-z_]\w*");

  void skipWhitespace() {
    while (inp.length > 0 && inp.substring(0, 1).trimLeft() == "") inp = inp.substring(1);
  }

  Lambda readNumber() {
    var num = readPattern(r"\d+");
    if (num == null) return null;
    int n = int.parse(num);
    Exp o = new Ref("x");
    for (int i = 0; i < n; i++) o = new Apply(new Ref("f"), o);
    return new Lambda("f", new Lambda("x", o));
  }

  Lambda readLambda() {
    var res = new RegExp(verbose ?
    r"(?:lambda |λ|\^|\\)((?:[A-Za-z_]\w*[₀₁₂₃₄₅₆₇₈₉]+ ?)+)\." :
    r"(?:lambda |λ|\^|\\)((?:[A-Za-z_]\w* ?)+)\."
    ).matchAsPrefix(inp);
    if (res == null) return null;
    inp = inp.substring(res.group(0).length);
    var o = readExp();
    res
        .group(1)
        .split(" ")
        .reversed
        .forEach((e) {
      if (verbose) {
        var mt = new RegExp(r"([A-Za-z_]\w*)([₀₁₂₃₄₅₆₇₈₉]+)").matchAsPrefix(e);
        o = new Lambda(mt.group(1), o)..id = fromSubscript(mt.group(2));
      } else {
        o = new Lambda(e, o);
      }
    });
    return o;
  }

  Ref readRef() {
    var name = readWord();
    if (name == null) return null;
    if (verbose) {
      return new Ref(name)..bound = fromSubscript(readPattern("[₀₁₂₃₄₅₆₇₈₉]+"));
    }
    return new Ref(name);
  }

  Sub readSub(List<Exp> l) {
    if (readPattern(r"\[") == null) return null;
    if (l.length == 0) {
      throw "Unexpected substitution at `$inp`";
    }
    skipWhitespace();
    var name = readWord();
    if (name == null) throw "Name expected at `$inp`";
    skipWhitespace();
    if (readPattern("=>") == null && readPattern("⇒") == null &&
        readPattern("=") == null && readPattern(r"\->") == null)
      throw "Arrow expected at `$inp`";
    skipWhitespace();
    Exp to;
    if ((to = readExp()) == null) throw "Expression expected at `$inp`";
    skipWhitespace();
    if (readPattern(r"\]") == null) {
      throw "']' Expected at `$inp`";
    }
    var o = new Sub(l.last, name, to);
    l.removeLast();
    return o;
  }

  Exp readSubExp() {
    if (readPattern(r"\(") == null) return null;
    var o = readExp();
    if (readPattern(r"\)") == null) {
      throw "')' Expected at `$inp`";
    }
    return o;
  }

  Exp readExp() {
    skipWhitespace();
    List<Exp> l = [];
    while (true) {
      skipWhitespace();
      Exp a = readLambda() ?? readNumber() ?? readRef() ?? readSub(l) ?? readSubExp();
      if (a == null) break;
      l.add(a);
    }
    return Exp.fromList(l);
  }
}

Exp parse(String inp, bool verbose) {
  var p = new Parser(inp, verbose);
  var out = p.readExp();
  if (p.inp.isNotEmpty) {
    throw "EOF expected at `${p.inp}`";
  }
  return out;
}

class LambdaModule extends TangentModule {


}
