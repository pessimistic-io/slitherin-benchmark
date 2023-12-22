// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import "./Math.sol";
import "./SafeMath.sol";

// import "forge-std/console.sol";

library OptimalDeposit {
  using SafeMath for uint256;

  function optimalDeposit(
    uint256 _amountA,
    uint256 _amountB,
    uint256 _reserveA,
    uint256 _reserveB,
    uint256 _fee
  ) internal view returns (uint256, bool) {
    uint256 swapAmt;
    bool isReversed;

    if (_amountA * _reserveB >= _amountB * _reserveA) {
      swapAmt = _optimalDeposit(_amountA, _amountB, _reserveA, _reserveB, _fee);
      isReversed = false;
    } else {
      swapAmt = _optimalDeposit(_amountB, _amountA, _reserveB, _reserveA, _fee);
      isReversed = true;
    }

    return (swapAmt, isReversed);
  }

    function optimalDepositTwoFees(
    uint256 _amountA,
    uint256 _amountB,
    uint256 _reserveA,
    uint256 _reserveB,
    uint256 _feeA,
    uint256 _feeB
  ) internal view returns (uint256, bool) {
    uint256 swapAmt;
    bool isReversed;

    if (_amountA * _reserveB >= _amountB * _reserveA) {
      swapAmt = _optimalDeposit(_amountA, _amountB, _reserveA, _reserveB, _feeA);
      isReversed = false;
    } else {
      swapAmt = _optimalDeposit(_amountB, _amountA, _reserveB, _reserveA, _feeB);
      isReversed = true;
    }

    return (swapAmt, isReversed);
  }

  function _optimalDeposit(
    uint256 _amountA,
    uint256 _amountB,
    uint256 _reserveA,
    uint256 _reserveB,
    uint256 _fee
  ) internal view returns (uint256) {
      require(_amountA * _reserveB >= _amountB * _reserveA, "Reversed");

      uint256 a = 1000 - _fee;
      uint256 b = (2000 - _fee) * _reserveA;
      uint256 _c = (_amountA * _reserveB) - (_amountB * _reserveA);
      uint256 c = _c * 1000 / (_amountB + _reserveB) * _reserveA;
       uint256 d = a * c * 4;
      uint256 e = Math.sqrt(b * b + d);
      uint256 numerator = e - b;
      uint256 denominator = a * 2;

      return numerator / denominator;
  }

  function optimalDepositStablePool(
    uint256 _amountA,
    uint256 _amountB,
    uint256 _reserveA,
    uint256 _reserveB,
    uint256 _decimalsA,
    uint256 _decimalsB
  ) external pure returns (uint256) {
    uint256 num;
    uint256 den;
    {
        uint256 a = _amountA.mul(1e18).div(_decimalsA);
        uint256 b = _amountB.mul(1e18).div(_decimalsB);
        uint256 x = _reserveA.mul(1e18).div(_decimalsA);
        uint256 y = _reserveB.mul(1e18).div(_decimalsB);
        uint256 p;
        {
            uint256 x2 = x.mul(x).div(1e18);
            uint256 y2 = y.mul(y).div(1e18);
            p = y.mul(x2.mul(3).add(y2).mul(1e18).div(y2.mul(3).add(x2))).div(x);
        }
        num = a.mul(y).sub(b.mul(x));
        den = a.add(x).mul(p).div(1e18).add(y).add(b);
    }

    return num.div(den).mul(_decimalsA).div(1e18);
  }

}

