// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.8;

import {IUniswapV3PoolState} from "./IUniswapV3PoolState.sol";

import {UniswapImmutableState} from "./UniswapV3SwapCallback.sol";

import {UniswapV3FactoryLibrary} from "./UniswapV3Factory.sol";
import {UniswapV3PoolQuoterLibrary} from "./UniswapV3PoolQuoter.sol";

import {UniswapV3SwapParam} from "./SwapParam.sol";

abstract contract SwapQuoterGetTotalToken is UniswapImmutableState {
  using UniswapV3PoolQuoterLibrary for address;

  function quoteSwapGetTotalToken(
    address token0,
    address token1,
    uint256 strike,
    uint24 uniswapV3Fee,
    address to,
    bool isToken0,
    uint256 token0Amount,
    uint256 token1Amount,
    bool removeStrikeLimit
  ) internal returns (uint256 tokenAmount, uint160 uniswapV3SqrtPriceAfter) {
    tokenAmount = isToken0 ? token0Amount : token1Amount;

    address pool = UniswapV3FactoryLibrary.getWithCheck(uniswapV3Factory, token0, token1, uniswapV3Fee);

    if ((isToken0 ? token1Amount : token0Amount) != 0) {
      bytes memory data = abi.encode(token0, token1, uniswapV3Fee);
      data = abi.encode(true, data);

      uint256 tokenAmountOut;
      (, tokenAmountOut, uniswapV3SqrtPriceAfter) = pool.quoteSwap(
        UniswapV3SwapParam({
          recipient: to,
          zeroForOne: !isToken0,
          exactInput: true,
          amount: isToken0 ? token1Amount : token0Amount,
          strikeLimit: removeStrikeLimit ? 0 : strike,
          data: data
        })
      );

      tokenAmount += tokenAmountOut;
    } else (uniswapV3SqrtPriceAfter, , , , , , ) = IUniswapV3PoolState(pool).slot0();
  }
}

