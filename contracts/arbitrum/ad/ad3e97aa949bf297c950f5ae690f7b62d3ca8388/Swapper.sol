// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0 <0.8.0;
pragma abicoder v2;

import { SafeERC20 } from "./SafeERC20.sol";
import { ERC20 } from "./ERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import { IUniswapV3Factory } from "./IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "./IUniswapV3Pool.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { Helper } from "./Helper.sol";

contract Swapper {
  using SafeERC20 for ERC20;
  using SafeMath for uint256;

  uint16 private constant RESOLUTION = 10_000;
  address private immutable UNISWAP_V3_FACTORY;
  address private immutable UNISWAP_V3_ROUTER;

  constructor(address uniswapV3Factory_, address uniswapV3Router_) {
    UNISWAP_V3_FACTORY = uniswapV3Factory_;
    UNISWAP_V3_ROUTER = uniswapV3Router_;
  }

  struct SwapParameters {
    address recipient;
    address tokenIn;
    address tokenOut;
    uint24 fee;
    uint256 amountIn;
    uint16 slippage;
    uint32 oracleSeconds;
  }

  function swap(SwapParameters memory params) external returns (uint256 amountOut) {
    IUniswapV3Pool swapPool = IUniswapV3Pool(
      IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(params.tokenIn, params.tokenOut, params.fee)
    );

    ERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
    ERC20(params.tokenIn).safeIncreaseAllowance(UNISWAP_V3_ROUTER, params.amountIn);

    uint160 sqrtPriceX96 = (params.oracleSeconds == 0)
      ? Helper.sqrtPriceX96(swapPool)
      : Helper.oracleSqrtPricex96(swapPool, params.oracleSeconds);

    uint256 expectedAmountOut = params.tokenOut == swapPool.token0()
      ? Helper.convert1ToToken0(sqrtPriceX96, params.amountIn, ERC20(swapPool.token0()).decimals())
      : Helper.convert0ToToken1(sqrtPriceX96, params.amountIn, ERC20(swapPool.token0()).decimals());

    uint256 amountOutMinimum = _applySlippageTolerance(false, expectedAmountOut, params.slippage);

    uint160 sqrtPriceLimitX96 = params.tokenIn == swapPool.token1()
      ? uint160(_applySlippageTolerance(true, uint256(Helper.sqrtPriceX96(swapPool)), params.slippage))
      : uint160(_applySlippageTolerance(false, uint256(Helper.sqrtPriceX96(swapPool)), params.slippage));

    amountOut = ISwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(
      ISwapRouter.ExactInputSingleParams({
        tokenIn: params.tokenIn,
        tokenOut: params.tokenOut,
        fee: params.fee,
        recipient: params.recipient,
        deadline: block.timestamp,
        amountIn: params.amountIn,
        amountOutMinimum: amountOutMinimum,
        sqrtPriceLimitX96: sqrtPriceLimitX96
      })
    );
  }

  function _applySlippageTolerance(
    bool _positive,
    uint256 _amount,
    uint16 _slippage
  ) internal pure returns (uint256 _amountAfterSlippage) {
    _amountAfterSlippage = _positive
      ? (_amount.mul(_slippage).div(RESOLUTION)).add(_amount)
      : _amount.sub(_amount.mul(_slippage).div(RESOLUTION));
  }
}

