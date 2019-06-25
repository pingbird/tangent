import 'dart:math';
import 'package:quiver/core.dart';

class BigFraction {
  const BigFraction(this.unm, this.dnm);
  final BigInt unm;
  final BigInt dnm;

  factory BigFraction.from(double n) {
    int b = 1;
    while (n.remainder(1) != 0) {
      n *= 2;
      b *= 2;
    }
    return BigFraction(BigInt.from(n), BigInt.from(b));
  }

  BigFraction.fromInt(int n) : unm = BigInt.from(n), dnm = BigInt.one;

  BigFraction.fromBigInt(BigInt n) : unm = n, dnm = BigInt.one;

  BigFraction normalize() {
    var gcd = unm.gcd(dnm);
    if (gcd == BigInt.one) return this;
    return BigFraction(unm ~/ gcd, dnm ~/ gcd);
  }

  get hashCode => hash2(unm, dnm);
  operator==(other) =>
    other is BigFraction &&
    other.unm == unm &&
    other.dnm == dnm;
}