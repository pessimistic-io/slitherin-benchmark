// SPDX-License-Identifier: BSD-3-Clause
pragma solidity >=0.6.0 <0.8.0;
import "./IUniswapV3Pool.sol";
import "./TickMath.sol";
import "./FixedPoint96.sol";
import "./FullMath.sol";

// 0.6.x version of SafeMath
library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

interface SwapMockToken {
  function decimals() external view returns (uint256);
}

contract TwapGetter {
  function getSqrtTwapX96(address uniswapV3Pool, uint32 twapInterval) public view returns (uint160 sqrtPriceX96) {
    if (twapInterval == 0) {
      // return the current price if twapInterval == 0
      (sqrtPriceX96, , , , , , ) = IUniswapV3Pool(uniswapV3Pool).slot0();
    } else {
      uint32[] memory secondsAgos = new uint32[](2);
      secondsAgos[0] = twapInterval; // from (before)
      secondsAgos[1] = 0; // to (now)

      (int56[] memory tickCumulatives, ) = IUniswapV3Pool(uniswapV3Pool).observe(secondsAgos);

      // tick(imprecise as it's an integer) to price
      sqrtPriceX96 = TickMath.getSqrtRatioAtTick(
        int24((tickCumulatives[1] - tickCumulatives[0]) / twapInterval)
      );
    }
    return sqrtPriceX96;
  }

  function getPriceX96FromSqrtPriceX96(uint160 sqrtPriceX96) public pure returns(uint256 priceX96) {
    return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
  }
}

contract TndOracle is TwapGetter {
  using SafeMath for uint256;

  function pow(uint256 base, uint256 exponent) public pure returns (uint256) {
    return base ** exponent;
  }

  function getTndPrice (uint32 twapInterval) public view returns (uint256) {
    address pool = 0x88B553F99bf8Cc6c18435C0c19D4d9B433d83645;
    uint160 sqrtPriceX96 = getSqrtTwapX96(pool, twapInterval);
    uint256 numerator = pow(sqrtPriceX96, 2).mul(pow(10, 30));
    uint256 denominator = pow(2, 192);
    uint256 price = numerator.div(denominator);
    return price;
  }
}


