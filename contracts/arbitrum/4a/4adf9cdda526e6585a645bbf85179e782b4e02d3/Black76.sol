//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./PRBMathSD59x18.sol";

contract Black76 {
  using PRBMathSD59x18 for int256;

  uint256 constant percentagePrecision = 10**9;
  int256 constant inputPrecision = 10**3;

  // Magic numbers
  int256 constant b1 = 319381530;
  int256 constant b2 = -356563782;
  int256 constant b3 = 1781477937;
  int256 constant b4 = -1821255978;
  int256 constant b5 = 1330274429;
  int256 constant p = 231641900;
  int256 constant c2 = 398942300;

  function getPrice(
    int256 forwardRate,
    int256 strike,
    int256 volatility,
    int256 timeToExpiry,
    int256 epochTime,
    int256 notional
  ) public view returns (int256, int256) {
    int256 d1;
    int256 d2;
    int256 call;
    int256 put;
    d1 = (forwardRate).ln() - (strike).ln();
    d1 += (volatility**2 * timeToExpiry * 10**18) / 36500 / 10**6 / 2;
    d1 *= 10**18;
    d1 =
      (d1 /
        ((volatility * timeToExpiry.sqrt() * 10**18) / int256(36500).sqrt())) *
      10**3;
    d2 =
      ((volatility * timeToExpiry.sqrt() * 10**18) / int256(36500).sqrt()) /
      10**3;
    d2 = d1 - d2;

    call = forwardRate * N(d1) - strike * N(d2);
    put = strike * N(-1 * d2) - forwardRate * N(-1 * d1);
    call = (call * notional * epochTime) / 36500 / 10**19; // 10 ** 18 precision
    put = (put * notional * epochTime) / 36500 / 10**19; // 10 ** 18 precision
    return (call, put);
  }

  function N(int256 z) public view returns (int256) {
    int256 a = abs(z);
    // if (a > 6 * 10**18) {
    //   return 10**18;
    // }
    int256 t = 10**39 / (10**27 + a * p); // 10 ** 12
    int256 b = c2 * int256((-1 * z * (z / 2)) / 10**18).exp(); // 10 ** 27
    int256 n = (((b5 * t) / 10**3) / 10**9) + b4;
    n = ((n * t) / 10**3) / 10**9 + b3;
    n = ((n * t) / 10**3) / 10**9 + b2;
    n = ((n * t) / 10**3) / 10**9 + b1;
    n = ((n * t) / 10**3) / 10**9;
    n = 10**9 - (((b / 10**18) * n) / 10**9);

    if (z < 0) {
      n = 10**9 - n;
    }
    return n;
  }

  function abs(int256 x) private pure returns (int256) {
    return x >= 0 ? x : -x;
  }
}

