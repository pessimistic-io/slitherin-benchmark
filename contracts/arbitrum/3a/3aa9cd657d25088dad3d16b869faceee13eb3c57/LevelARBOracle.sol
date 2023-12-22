// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20.sol";
import "./ILiquidityPool.sol";
import "./IPoolLens.sol";
import "./ILiquidityCalculator.sol";
import "./ILevelOracle.sol";
import "./Errors.sol";

contract LevelARBOracle {
  /* ========== STATE VARIABLES ========== */

  // SLLP token address router contract
  address public immutable SLLP;
  // MLLP token address router contract
  address public immutable MLLP;
  // JLLP token address router contract
  address public immutable JLLP;
  // Level liquidity pool
  ILiquidityPool public immutable liquidityPool;
  // Level Pool lens contract
  IPoolLens public immutable poolLens;
  // Level liquidity calculator
  ILiquidityCalculator public immutable liquidityCalculator;
  // Level official oracle
  ILevelOracle public immutable levelOracle;

  /* ========== CONSTANTS ========== */

  uint256 constant SAFE_MULTIPLIER = 1e18;

  /* ========== MAPPINGS ========== */

  // Mapping of approved token in (SLLP, MLLP, JLLP)
  mapping(address => bool) public tokenIn;

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _SLLP SLLP token address
    * @param _MLLP MLLP token address
    * @param _JLLP JLLP token address
    * @param _liquidityPool Level liquidity pool address
    * @param _poolLens Level pool lens address
    * @param _liquidityCalculator Level liquidity calculator address
    * @param _levelOracle Level official oracle address
  */
  constructor(
    address _SLLP,
    address _MLLP,
    address _JLLP,
    address _liquidityPool,
    address _poolLens,
    address _liquidityCalculator,
    address _levelOracle
  ) {
    require(_SLLP != address(0), "Invalid address");
    require(_MLLP != address(0), "Invalid address");
    require(_JLLP != address(0), "Invalid address");
    require(_liquidityPool != address(0), "Invalid address");
    require(_poolLens != address(0), "Invalid address");
    require(_liquidityCalculator != address(0), "Invalid address");
    require(_levelOracle != address(0), "Invalid address");

    SLLP = _SLLP;
    MLLP = _MLLP;
    JLLP = _JLLP;

    tokenIn[SLLP] = true;
    tokenIn[MLLP] = true;
    tokenIn[JLLP] = true;

    liquidityPool = ILiquidityPool(_liquidityPool);
    poolLens = IPoolLens(_poolLens);
    liquidityCalculator = ILiquidityCalculator(_liquidityCalculator);
    levelOracle = ILevelOracle(_levelOracle);
  }

  /* ========== VIEW FUNCTIONS ========== */

  /**
    * Get price of an LLP in USD value in 1e30
    * @param _token  Address of LLP
    * @param _bool true for maximum price, false for minimum price
    * @return  Amount of LLP in
  */
  function getLLPPrice(address _token, bool _bool) public view returns (uint256) {
    if (!tokenIn[_token]) revert Errors.InvalidTokenIn();

    // get tranche value (in 1e30)
    uint256 llpValue = poolLens.getTrancheValue(_token, _bool);

    // get total supply of tranche LLP tokens (in 1e18)
    uint256 totalSupply = IERC20(_token).totalSupply();

    // get estimated token value of 1 LLP in 1e30
    // note this returns price in 1e18 not 1e30; to remove * 1e12
    return (llpValue * SAFE_MULTIPLIER) / (totalSupply); // to normalize to 1e30
  }

  /**
    * Used to get how much LLP in is required to get amtOut of tokenOut
    * Reverse flow of Level pool removeLiquidity()
    * lpAmt = valueChange * totalSupply / trancheValue
    * valueChange = outAmount * tokenPrice
    * outAmount = outAmountAfterFees * (precision - fee) / precision
    * fee obtained from level's liquidity calculator contract
    * @param _amtOut  Amount of tokenOut wanted
    * @param _tokenIn  Address of LLP
    * @param _tokenOut  Address of token to get out
    * @return  Amount of LLP in
  */
  function getLLPAmountIn(
    uint256 _amtOut,
    address _tokenIn,
    address _tokenOut
  ) public view returns (uint256) {
    if (!tokenIn[_tokenIn]) revert Errors.InvalidTokenIn();
    if (!liquidityPool.isAsset(_tokenOut)) revert Errors.InvalidTokenOut();

    // if _amtOut is 0, just return 0 for LLP amount in as well
    if (_amtOut == 0) return 0;

    // from level poolStorage.sol
    uint256 PRECISION = 1e10;

    // returns price relative to token decimals. e.g.
    // USDT returns in 1e24 as it is 1e6, WBTC in 1e22 as token has 1e8
    // WETH in 1e12 as token has 1e18; price decimals * token decimals = 1e30
    uint256 tokenOutPrice = levelOracle.getPrice(_tokenOut, true);

    // value in 1e30
    uint256 estimatedUSDValue = _amtOut * tokenOutPrice;

    uint256 fee = liquidityCalculator.calcAddRemoveLiquidityFee(
      _tokenOut,
      tokenOutPrice,
      estimatedUSDValue,
      false
    );
    // amount in 1e18
    uint256 outAmountBeforeFees = (_amtOut + 10) * PRECISION / (PRECISION - fee);

    // valueChange in 1e30
    uint256 valueChange = outAmountBeforeFees * tokenOutPrice;

    // trancheValue returned in 1e30
    uint256 trancheValue = poolLens.getTrancheValue(_tokenIn, false);

    // lpAmt in 1e18
    uint256 lpAmtIn = valueChange * IERC20(_tokenIn).totalSupply() / trancheValue;

    return lpAmtIn * 1.002e18 / 1e18;
  }

  /* ========== INTERNAL FUNCTIONS  ========== */

  /**
    * Internal function from Level's contracts
  */
  function _diff(uint256 a, uint256 b) internal pure returns (uint256) {
    unchecked {
      return a > b ? a - b : b - a;
    }
  }

  /**
    * Internal function from Level's contracts
  */
  function _zeroCapSub(uint256 a, uint256 b) internal pure returns (uint256) {
    unchecked {
      return a > b ? a - b : 0;
    }
  }
}

