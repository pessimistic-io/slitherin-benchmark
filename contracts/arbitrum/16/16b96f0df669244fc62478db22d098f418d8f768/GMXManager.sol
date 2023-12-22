// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20Metadata } from "./IERC20Metadata.sol";
import { ISwap } from "./ISwap.sol";
import { GMXTypes } from "./GMXTypes.sol";
import { GMXReader } from "./GMXReader.sol";
import { GMXWorker } from "./GMXWorker.sol";

library GMXManager {
  using SafeERC20 for IERC20;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

  /* ========== VIEW FUNCTIONS ========== */

  /**
    * @dev Check if swap between tokens is needed to ensure enough repayment for both tokens
    * @notice Assume that after swapping one token for the other, there is still enough to repay both
    * @param self Vault store data
    * @param rp GMXTypes.RepayParams struct
    * @return (swapNeeded, tokenFrom, tokenTo, tokenToAmt)
  */
  function calcSwapForRepay(
    GMXTypes.Store storage self,
    GMXTypes.RepayParams memory rp
  ) external view returns (bool, address, address, uint256) {
    address _tokenFrom;
    address _tokenTo;
    uint256 _tokenToAmt;

    if (rp.repayTokenAAmt > self.tokenA.balanceOf(address(this))) {
      // If more tokenA is needed for repayment
      _tokenToAmt = rp.repayTokenAAmt - self.tokenA.balanceOf(address(this));
      _tokenFrom = address(self.tokenB);
      _tokenTo = address(self.tokenA);

      return (true, _tokenFrom, _tokenTo, _tokenToAmt);
    } else if (rp.repayTokenBAmt > self.tokenB.balanceOf(address(this))) {
      // If more tokenB is needed for repayment
      _tokenToAmt = rp.repayTokenBAmt - self.tokenB.balanceOf(address(this));
      _tokenFrom = address(self.tokenA);
      _tokenTo = address(self.tokenB);

      return (true, _tokenFrom, _tokenTo, _tokenToAmt);
    } else {
      // If more there is enough to repay both tokens
      return (false, address(0), address(0), 0);
    }
  }

  /**
    * @dev Calculate how much tokens to borrow
    * @param self Vault store data
    * @param depositValue  Deposit value (USD) in 1e18
  */
  function calcBorrow(
    GMXTypes.Store storage self,
    uint256 depositValue
  ) external view returns (uint256, uint256) {
    // Calculate final position value based on deposit value
    uint256 _positionValue = depositValue * self.leverage / SAFE_MULTIPLIER;
    // Obtain the value to borrow
    uint256 _borrowValue = _positionValue - depositValue;

    uint256 _tokenADecimals = IERC20Metadata(address(self.tokenA)).decimals();
    uint256 _tokenBDecimals = IERC20Metadata(address(self.tokenB)).decimals();
    uint256 _borrowLongTokenAmt;
    uint256 _borrowShortTokenAmt;

    // If delta is long, borrow all in short token
    if (self.delta == GMXTypes.Delta.Long) {
      _borrowShortTokenAmt = _borrowValue * SAFE_MULTIPLIER
                             / GMXReader.convertToUsdValue(self, address(self.tokenB), 10**(_tokenBDecimals))
                             / (10 ** (18 - _tokenBDecimals));
    }

    // If delta is neutral, borrow appropriate amount in long token to hedge, and the rest in short token
    if (self.delta == GMXTypes.Delta.Neutral) {
      // Get token weights in LP, e.g. 50% = 5e17
      (uint256 _tokenAWeight,) = GMXReader.tokenWeights(self);

      // Get value of long token (typically tokenA)
      uint256 _longTokenWeightedValue = _tokenAWeight * _positionValue / SAFE_MULTIPLIER;

      // Borrow appropriate amount in long token to hedge
      _borrowLongTokenAmt = _longTokenWeightedValue * SAFE_MULTIPLIER
                            / GMXReader.convertToUsdValue(self, address(self.tokenA), 10**(_tokenADecimals))
                            / (10 ** (18 - _tokenADecimals));

      // Borrow the shortfall value in short token
      _borrowShortTokenAmt = (_borrowValue - _longTokenWeightedValue) * SAFE_MULTIPLIER
                             / GMXReader.convertToUsdValue(self, address(self.tokenB), 10**(_tokenBDecimals))
                             / (10 ** (18 - _tokenBDecimals));
    }

    return (_borrowLongTokenAmt, _borrowShortTokenAmt);
  }

  /**
    * @dev Calculate how much tokens to repay
    * @param self Vault store data
    * @param shareRatio Amount of svTokens relative to total supply of svTokens in 1e18
  */
  function calcRepay(
    GMXTypes.Store storage self,
    uint256 shareRatio
  ) external view returns (uint256, uint256) {
    (uint256 tokenADebtAmt, uint256 tokenBDebtAmt) = GMXReader.debtAmt(self);

    uint256 _repayTokenAAmt = shareRatio * tokenADebtAmt / SAFE_MULTIPLIER;
    uint256 _repayTokenBAmt = shareRatio * tokenBDebtAmt / SAFE_MULTIPLIER;

    return (_repayTokenAAmt, _repayTokenBAmt);
  }

  /**
    * @dev Calculate minimum market tokens to receive on adding liquidity
    * @param self Vault store data
    * @param depositValue Deposit value (USD) in 1e18
    * @param slippage Slippage value in 1e4
    * @return minMarketTokenAmt in 1e18
  */
  function calcMinMarketSlippageAmt(
    GMXTypes.Store storage self,
    uint256 depositValue,
    uint256 slippage
  ) external view returns (uint256) {
    uint256 _lpTokenValue = self.gmxOracle.getLpTokenValue(
      address(self.lpToken),
      address(self.tokenA),
      address(self.tokenA),
      address(self.tokenB),
      false,
      false
    );

    return depositValue
      * SAFE_MULTIPLIER
      / _lpTokenValue
      * (10000 - slippage) / 10000;
  }

  /**
    * @dev Calculate minimum tokens to receive on removing liquidity
    * @notice minLongToken and minShortToken should be the token which we want to receive
    * after liquidity withdrawal and swap
    * @param self Vault store data
    * @param lpAmt Amt of lp tokens to remove liquidity in 1e18
    * @param minLongToken Address of token to receive longToken in
    * @param minShortToken Address of token to receive shortToken in
    * @param slippage Slippage value in 1e4
    * @return (minTokenAAmt, minTokenBAmt) in 1e18
  */
  function calcMinTokensSlippageAmt(
    GMXTypes.Store storage self,
    uint256 lpAmt,
    address minLongToken,
    address minShortToken,
    uint256 slippage
  ) external view returns (uint256, uint256) {
    uint256 _withdrawValue = lpAmt
      * self.gmxOracle.getLpTokenValue(
        address(self.lpToken),
        address(self.tokenA),
        address(self.tokenA),
        address(self.tokenB),
        false,
        false
      )
      / SAFE_MULTIPLIER;

    (uint256 _tokenAWeight, uint256 _tokenBWeight) = GMXReader.tokenWeights(self);

    uint256 _minLongTokenAmt = _withdrawValue
      * _tokenAWeight / SAFE_MULTIPLIER
      * SAFE_MULTIPLIER
      / GMXReader.convertToUsdValue(
        self,
        minLongToken,
        10**(IERC20Metadata(minLongToken).decimals())
      )
      / (10 ** (18 - IERC20Metadata(minLongToken).decimals()));

    uint256 _minShortTokenAmt = _withdrawValue
      * _tokenBWeight / SAFE_MULTIPLIER
      * SAFE_MULTIPLIER
      / GMXReader.convertToUsdValue(
        self,
        minShortToken,
        10**(IERC20Metadata(minShortToken).decimals())
      )
      / (10 ** (18 - IERC20Metadata(minShortToken).decimals()));

    return (
      _minLongTokenAmt * (10000 - slippage) / 10000,
      _minShortTokenAmt * (10000 - slippage) / 10000
    );
  }


  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * @dev Borrow tokens from lending vaults
    * @param self Vault store data
    * @param borrowTokenAAmt Amount of tokenA to borrow in token decimals
    * @param borrowTokenBAmt Amount of tokenB to borrow in token decimals
  */
  function borrow(
    GMXTypes.Store storage self,
    uint256 borrowTokenAAmt,
    uint256 borrowTokenBAmt
  ) public {
    if (borrowTokenAAmt > 0) {
      self.tokenALendingVault.borrow(borrowTokenAAmt);
    }
    if (borrowTokenBAmt > 0) {
      self.tokenBLendingVault.borrow(borrowTokenBAmt);
    }
  }

  /**
    * @dev Repay tokens to lending vaults
    * @param self Vault store data
    * @param repayTokenAAmt Amount of tokenA to repay in token decimals
    * @param repayTokenBAmt Amount of tokenB to repay in token decimals
  */
  function repay(
    GMXTypes.Store storage self,
    uint256 repayTokenAAmt,
    uint256 repayTokenBAmt
  ) public {
    if (repayTokenAAmt > 0) {
      self.tokenALendingVault.repay(repayTokenAAmt);
    }
    if (repayTokenBAmt > 0) {
      self.tokenBLendingVault.repay(repayTokenBAmt);
    }
  }

  /**
    * @dev Called by deposit function add liquidity
    * @param self Vault store data
    * @param alp GMXTypes.AddLiquidityParams
    * @return depositKey
  */
  function addLiquidity(
    GMXTypes.Store storage self,
    GMXTypes.AddLiquidityParams memory alp
  ) public returns (bytes32) {
    return GMXWorker.addLiquidity(self, alp);
  }

  /**
    * @dev Called by withdraw function to remove liquidity
    * @param self Vault store data
    * @param rlp GMXTypes.RemoveLiquidityParams
    * @return withdrawKey
  */
  function removeLiquidity(
    GMXTypes.Store storage self,
    GMXTypes.RemoveLiquidityParams memory rlp
  ) public returns (bytes32) {
    return GMXWorker.removeLiquidity(self, rlp);
  }

  /**
    * @dev Swap exact amount of tokenIn for as many amount of tokenOut
    * @notice Utilizing Uniswap
    * @param self Vault store data
    * @param sp ISwap.SwapParams struct
    * @return amountOut Amount of tokens out in token decimals
  */
  function swapExactTokensForTokens(
    GMXTypes.Store storage self,
    ISwap.SwapParams memory sp
  ) external returns (uint256) {
    if (sp.amountIn > 0) {
      return GMXWorker.swapExactTokensForTokens(self, sp);
    } else {
      return 0;
    }
  }

  /**
    * @dev Swap as little tokenIn for exact amount of tokenOut
    * @notice Utilizing Uniswap
    * @param self Vault store data
    * @param sp ISwap.SwapParams struct
    * @return amountIn Amount of tokens in in token decimals
  */
  function swapTokensForExactTokens(
    GMXTypes.Store storage self,
    ISwap.SwapParams memory sp
  ) external returns (uint256) {
    if (sp.amountIn > 0) {
      return GMXWorker.swapTokensForExactTokens(self, sp);
    } else {
      return 0;
    }
  }
}

