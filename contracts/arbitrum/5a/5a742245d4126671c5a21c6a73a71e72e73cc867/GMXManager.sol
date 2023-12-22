// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20Metadata } from "./IERC20Metadata.sol";
import { ISwap } from "./ISwap.sol";
import { GMXTypes } from "./GMXTypes.sol";
import { GMXReader } from "./GMXReader.sol";
import { GMXWorker } from "./GMXWorker.sol";

/**
  * @title GMXManager
  * @author Steadefi
  * @notice Re-usable library functions for calculations and operations of borrows, repays, swaps
  * adding and removal of liquidity to yield source
*/
library GMXManager {
  using SafeERC20 for IERC20;

  /* ====================== CONSTANTS ======================== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

  /* ======================== EVENTS ========================= */

  event BorrowSuccess(uint256 borrowTokenAAmt, uint256 borrowTokenBAmt);
  event RepaySuccess(uint256 repayTokenAAmt, uint256 repayTokenBAmt);

  /* ===================== VIEW FUNCTIONS ==================== */

  /**
    * @notice Calculate if token swap is needed to ensure enough repayment for both tokenA and tokenB
    * @notice Assume that after swapping one token for the other, there is still enough to repay both tokens
    * @param self GMXTypes.Store
    * @param rp GMXTypes.RepayParams
    * @param tokenAAmt Amount of tokenA
    * @param tokenBAmt Amount of tokenB
    * @return swapNeeded boolean if swap is needed
    * @return tokenFrom address of token to swap from
    * @return tokenTo address of token to swap to
    * @return tokenToAmt amount of tokenFrom to swap in token decimals
  */
  function calcSwapForRepay(
    GMXTypes.Store storage self,
    GMXTypes.RepayParams memory rp,
    uint256 tokenAAmt,
    uint256 tokenBAmt
  ) external view returns (bool, address, address, uint256) {
    address _tokenFrom;
    address _tokenTo;
    uint256 _tokenToAmt;

    if (rp.repayTokenAAmt > tokenAAmt) {
      // If more tokenA is needed for repayment
      _tokenToAmt = rp.repayTokenAAmt - tokenAAmt;
      _tokenFrom = address(self.tokenB);
      _tokenTo = address(self.tokenA);

      return (true, _tokenFrom, _tokenTo, _tokenToAmt);
    } else if (rp.repayTokenBAmt > tokenBAmt) {
      // If more tokenB is needed for repayment
      _tokenToAmt = rp.repayTokenBAmt - tokenBAmt;
      _tokenFrom = address(self.tokenA);
      _tokenTo = address(self.tokenB);

      return (true, _tokenFrom, _tokenTo, _tokenToAmt);
    } else {
      // If more there is enough to repay both tokens
      return (false, address(0), address(0), 0);
    }
  }

  /**
    * @notice Calculate amount of tokenA and tokenB to borrow
    * @param self GMXTypes.Store
    * @param depositValue USD value in 1e18
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

    // If delta is short, borrow all in long token
    if (self.delta == GMXTypes.Delta.Short) {
      _borrowLongTokenAmt = _borrowValue * SAFE_MULTIPLIER
                             / GMXReader.convertToUsdValue(self, address(self.tokenA), 10**(_tokenADecimals))
                             / (10 ** (18 - _tokenADecimals));
    }

    return (_borrowLongTokenAmt, _borrowShortTokenAmt);
  }

  /**
    * @notice Calculate amount of tokenA and tokenB to repay based on token shares ratio being withdrawn
    * @param self GMXTypes.Store
    * @param shareRatio Amount of vault token shares relative to total supply in 1e18
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
    * @notice Calculate minimum market (GM LP) tokens to receive when adding liquidity
    * @param self GMXTypes.Store
    * @param depositValue USD value in 1e18
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
      true,
      false
    );

    return depositValue
      * SAFE_MULTIPLIER
      / _lpTokenValue
      * (10000 - slippage) / 10000;
  }

  /**
    * @notice Calculate minimum tokens to receive when removing liquidity
    * @dev minLongToken and minShortToken should be the token which we want to receive
    * after liquidity withdrawal and swap
    * @param self GMXTypes.Store
    * @param lpAmt Amt of lp tokens to remove liquidity in 1e18
    * @param minLongToken Address of token to receive longToken in
    * @param minShortToken Address of token to receive shortToken in
    * @param slippage Slippage value in 1e4
    * @return minTokenAAmt in 1e18
    * @return minTokenBAmt in 1e18
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
        true,
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

  /**
    * @notice Calculate maximum amount of tokenIn allowed when swapping for an exact
    * amount of tokenOut as a form of slippage protection
    * @dev We slightly buffer amountOut here with swapSlippage to account for fees, etc.
    * @param self GMXTypes.Store
    * @param tokenIn Address of tokenIn
    * @param tokenOut Address of tokenOut
    * @param amountOut Amt of tokenOut wanted
    * @return amountInMaximum in 1e18
  */
  function calcAmountInMaximum(
    GMXTypes.Store storage self,
    address tokenIn,
    address tokenOut,
    uint256 amountOut
  ) external view returns (uint256) {
    uint256 _amountInMaximum = amountOut
      * self.chainlinkOracle.consultIn18Decimals(tokenOut)
      / self.chainlinkOracle.consultIn18Decimals(tokenIn)
      * (10000 + self.swapSlippage) / 10000;

    // If tokenIn asset decimals is less than 18, e.g. USDC,
    // we need to normalize the decimals of _amountInMaximum
    if (IERC20Metadata(tokenIn).decimals() < 18)
      _amountInMaximum /= 10 ** (18 - IERC20Metadata(tokenIn).decimals());

    return _amountInMaximum;
  }

  /* ================== MUTATIVE FUNCTIONS =================== */

  /**
    * @notice Borrow tokens from lending vaults
    * @param self GMXTypes.Store
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

    emit BorrowSuccess(borrowTokenAAmt, borrowTokenBAmt);
  }

  /**
    * @notice Repay tokens to lending vaults
    * @param self GMXTypes.Store
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

    emit RepaySuccess(repayTokenAAmt, repayTokenBAmt);
  }

  /**
    * @notice Add liquidity to yield source
    * @param self GMXTypes.Store
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
    * @notice Remove liquidity from yield source
    * @param self GMXTypes.Store
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
    * @notice Swap exact amount of tokenIn for as many possible amount of tokenOut
    * @param self GMXTypes.Store
    * @param sp ISwap.SwapParams
    * @return amountOut in token decimals
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
    * @notice Swap as little posible tokenIn for exact amount of tokenOut
    * @param self GMXTypes.Store
    * @param sp ISwap.SwapParams
    * @return amountIn in token decimals
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

