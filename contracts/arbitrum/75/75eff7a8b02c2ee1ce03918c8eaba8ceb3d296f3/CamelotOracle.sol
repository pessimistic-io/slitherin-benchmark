// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Math.sol";
import "./IERC20.sol";
import "./ICamelotPair.sol";
import "./ICamelotFactory.sol";
import "./ICamelotRouter.sol";
import "./IChainlinkOracle.sol";

contract CamelotOracle {
  /* ========== STATE VARIABLES ========== */

  // Camelot factory
  ICamelotFactory public immutable factory;
  // Camelot router
  ICamelotRouter public immutable router;
  // Chainlink oracle
  IChainlinkOracle public immutable chainlinkOracle;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _factory Address of Camelot factory
    * @param _router Address of Camelot router
    * @param _chainlinkOracle Address of Chainlink oracle
  */
  constructor(ICamelotFactory _factory, ICamelotRouter _router, IChainlinkOracle _chainlinkOracle) {
    require(address(_factory) != address(0), "Invalid address");
    require(address(_router) != address(0), "Invalid address");
    require(address(_chainlinkOracle) != address(0), "Invalid address");

    factory = _factory;
    router = _router;
    chainlinkOracle = _chainlinkOracle;
  }

  /* ========== VIEW FUNCTIONS ========== */

  /**
    * Get the address of the Joe LP token for tokenA and tokenB
    * @param _tokenA Token A address
    * @param _tokenB Token B address
    * @return address Address of the Joe LP token
  */
  function lpToken(
    address _tokenA,
    address _tokenB
  ) public view returns (address) {
    return factory.getPair(_tokenA, _tokenB);
  }

  /**
    * Get token B amounts out with token A amounts in via swap liquidity pool
    * @param _amountIn Amount of token A in, expressed in token A's decimals
    * @param _tokenA Token A address
    * @param _tokenB Token B address
    * @param _pair LP token address
    * @return amountOut Amount of token B to be received, expressed in token B's decimals
  */
  function getAmountsOut(
    uint256 _amountIn,
    address _tokenA,
    address _tokenB,
    ICamelotPair _pair
  ) public view returns (uint256) {
    if (_amountIn == 0) return 0;
    require(address(_pair) != address(0), "invalid pool");
    require(
      _tokenA == _pair.token0() || _tokenA == _pair.token1(),
      "invalid token in pool"
    );
    require(
      _tokenB == _pair.token0() || _tokenB == _pair.token1(),
      "invalid token in pool"
    );

    address[] memory path = new address[](2);
    path[0] = _tokenA;
    path[1] = _tokenB;

    return router.getAmountsOut(_amountIn, path)[1];
  }

    /**
    * Helper function to calculate amountIn for swapExactTokensForTokens
    * @param _amountOut   Amt of token to receive in token decimals
    * @param _reserveIn   Reserve of token IN
    * @param _reserveOut  Reserve of token OUT
    * @param _fee         Fee paid on token IN
  */
  function getAmountsIn(
    uint256 _amountOut,
    uint256 _reserveIn,
    uint256 _reserveOut,
    uint256 _fee
  ) public pure returns (uint256) {
    require(_amountOut > 0, "Cannot swap 0");
    require(_reserveIn > 0 && _reserveOut > 0, "Invalid reserves");
    uint256 numerator = _reserveIn * _amountOut * 1000;
    uint256 denominator = (_reserveOut - _amountOut) * (1000 - (_fee / 100));
    return (numerator / denominator) + 1;
  }

  /**
    * Get token A and token B's respective reserves in an amount of LP token
    * @param _amount Amount of LP token, expressed in 1e18
    * @param _tokenA Token A address
    * @param _tokenB Token B address
    * @param _pair LP token address
    * @param _addProtocolFees Boolean to include pending protocol fees or not
    * @return (reserveA, reserveB) Reserve amount of Token A and B respectively, in 1e18
  */
  function getLpTokenReserves(
    uint256 _amount,
    address _tokenA,
    address _tokenB,
    ICamelotPair _pair,
    bool _addProtocolFees
  ) public view returns (uint256, uint256) {
    require(address(_pair) != address(0), "invalid pool");
    require(
      _tokenA == _pair.token0() || _tokenA == _pair.token1(),
      "invalid token in pool"
    );
    require(
      _tokenB == _pair.token0() || _tokenB == _pair.token1(),
      "invalid token in pool"
    );

    uint256 reserveA;
    uint256 reserveB;

    (uint256 reserve0, uint256 reserve1, , ) = _pair.getReserves();

    uint256 totalSupply;
    if (_addProtocolFees) {
      totalSupply = _pair.totalSupply() + getPendingProtocolFees(address(_pair));
    } else {
      totalSupply = _pair.totalSupply();
    }

    if (_tokenA == _pair.token0() && _tokenB == _pair.token1()) {
      reserveA = reserve0;
      reserveB = reserve1;
    } else {
      reserveA = reserve1;
      reserveB = reserve0;
    }

    reserveA = _amount * SAFE_MULTIPLIER / totalSupply * reserveA / SAFE_MULTIPLIER;
    reserveB = _amount * SAFE_MULTIPLIER / totalSupply * reserveB / SAFE_MULTIPLIER;

    return (reserveA, reserveB);
  }

  /**
    * Get token A and token B's respective fees for an LP token
    * @param _tokenA Token A address
    * @param _tokenB Token B address
    * @param _pair LP token address
    * @return (feeA, feeB) Reserve amount of Token A and B respectively, in 1e18
  */
  function getLpTokenFees(
    address _tokenA,
    address _tokenB,
    ICamelotPair _pair
  ) public view returns (uint16, uint16) {
    require(address(_pair) != address(0), "invalid pool");
    require(
      _tokenA == _pair.token0() || _tokenA == _pair.token1(),
      "invalid token in pool"
    );
    require(
      _tokenB == _pair.token0() || _tokenB == _pair.token1(),
      "invalid token in pool"
    );

    (, , uint16 fee0, uint16 fee1) = _pair.getReserves();

    if (_tokenA == _pair.token0() && _tokenB == _pair.token1()) {
      return (fee0, fee1);
    } else {
      return (fee1, fee0);
    }
  }

  /**
    * Get LP token fair value from amount
    * @param _amount Amount of LP token, expressed in 1e18
    * @param _tokenA Token A address
    * @param _tokenB Token B address
    * @param _pair LP token address
    * @return lpTokenValue Value of respective tokens; expressed in 1e8
  */
  function getLpTokenValue(
    uint256 _amount,
    address _tokenA,
    address _tokenB,
    ICamelotPair _pair
  ) public view returns (uint256) {
    uint256 totalSupply = _pair.totalSupply();

    (uint256 totalReserveA, uint256 totalReserveB) = getLpTokenReserves(
      totalSupply,
      _tokenA,
      _tokenB,
      _pair,
      false
    );

    uint256 sqrtK = Math.sqrt((totalReserveA * totalReserveB)) * 2**112 / totalSupply;

    // convert prices from Chainlink consult which is in 1e18 to 2**112
    uint256 priceA = chainlinkOracle.consultIn18Decimals(_tokenA)
                     * 10**8 / SAFE_MULTIPLIER
                     * 2**112 / 10**(18 - IERC20(_tokenA).decimals());
    uint256 priceB = chainlinkOracle.consultIn18Decimals(_tokenB)
                     * 10**8 / SAFE_MULTIPLIER
                     * 2**112 / 10**(18 - IERC20(_tokenB).decimals());

    uint256 lpFairValue = sqrtK * 2
                          * Math.sqrt(priceA) / 2**56
                          * Math.sqrt(priceB) / 2**56; // in 1e12

    uint256 lpFairValueIn18 = lpFairValue / 2**112
                              * 10**(36 - (IERC20(_tokenA).decimals() + IERC20(_tokenB).decimals()));

    return _amount * lpFairValueIn18 / SAFE_MULTIPLIER;
  }

  /**
    * Get token A and token B's LP token amount from value
    * @param _value Value of LP token, expressed in 1e8
    * @param _tokenA Token A address
    * @param _tokenB Token B address
    * @param _pair LP token address
    * @return lpTokenAmount Amount of LP tokens; expressed in 1e18
  */
  function getLpTokenAmount(
    uint256 _value,
    address _tokenA,
    address _tokenB,
    ICamelotPair _pair
  ) public view returns (uint256) {
    uint256 lpTokenValue = getLpTokenValue(
      _pair.totalSupply(),
      _tokenA,
      _tokenB,
      _pair
    );

    uint256 lpTokenAmount = _value * _pair.totalSupply() / lpTokenValue;

    return lpTokenAmount;
  }

  /**
    * Replicate _mintFee function from CamelotPair contract to calculate pending LP
    * tokens that will be minted as protocol fees
    * @param _pair LP token address
    * @return pendingFees Amount of pending fees
  */
  function getPendingProtocolFees(address _pair) public view returns (uint256) {
    ICamelotPair _lpToken = ICamelotPair(_pair);
    if (_lpToken.stableSwap()) return 0;

    (uint256 ownerFeeShare, address feeTo) = ICamelotFactory(_lpToken.factory()).feeInfo();

    bool feeOn = feeTo != address(0);
    uint256 _kLast = _lpToken.kLast();

    if (feeOn) {
      if (_kLast != 0 ) {
        (uint256 reserve0, uint256 reserve1,,) = _lpToken.getReserves();
        uint256 rootK = Math.sqrt(_k(_pair, reserve0, reserve1));
        uint256 rootKLast = Math.sqrt(_kLast);
        if (rootK > rootKLast) {
          uint256 d = (_lpToken.FEE_DENOMINATOR() * 100 / ownerFeeShare) - 100;
          uint256 numerator = _lpToken.totalSupply() * (rootK - rootKLast) * 100;
          uint256 denominator = rootK * d + (rootKLast * 100);
          uint256 liquidity = numerator / denominator;
          return liquidity;
        }
      }
    }
    return 0;
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
    * Replicate _k function from CamelotPair to calculate rootK
    * @param _pair LP token address
    * @param _balance0 token0 reserve amount
    * @param _balance1 token1 reserve amount
    * @return rootK value of rootK
  */
  function _k(address _pair, uint256 _balance0, uint256 _balance1) internal view returns (uint256) {
    if (ICamelotPair(_pair).stableSwap()) {
      uint256 _x = _balance0 * (1e18) / ICamelotPair(_pair).precisionMultiplier0();
      uint256 _y = _balance1 * (1e18) / ICamelotPair(_pair).precisionMultiplier1();
      uint256 _a = (_x * (_y)) / 1e18;
      uint256 _b = (_x * (_x) / 1e18) + (_y * (_y) / 1e18);
      return  _a * (_b) / 1e18; // x3y+y3x >= k
    }
    return _balance0 * (_balance1);
  }
}

