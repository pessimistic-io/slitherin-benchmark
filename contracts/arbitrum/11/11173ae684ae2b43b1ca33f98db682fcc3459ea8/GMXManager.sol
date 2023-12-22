// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20Metadata } from "./IERC20Metadata.sol";
import { GMXTypes } from "./GMXTypes.sol";
import { GMXReader } from "./GMXReader.sol";
import { GMXWorker } from "./GMXWorker.sol";

library GMXManager {
  using SafeERC20 for IERC20;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

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
    * @param dp GMXTypes.DepositParams
    * @return depositKey
  */
  function addLiquidity(
    GMXTypes.Store storage self,
    GMXTypes.DepositParams memory dp
  ) public returns (bytes32) {
    GMXTypes.AddLiquidityParams memory _alp;
    _alp.tokenAAmt = self.tokenA.balanceOf(address(this));
    _alp.tokenBAmt = self.tokenB.balanceOf(address(this));
    _alp.slippage = dp.slippage;
    _alp.executionFee = dp.executionFee;

    bytes32 _depositKey = GMXWorker.addLiquidity(self, _alp);

    return _depositKey;
  }

  /**
    * @dev Called by withdraw function to remove liquidity
    * @param self Vault store data
    * @param wp GMXTypes.WithdrawParams
    * @return withdrawKey
  */
  function removeLiquidity(
    GMXTypes.Store storage self,
    GMXTypes.WithdrawParams memory wp
  ) public returns (bytes32) {
    GMXTypes.RemoveLiquidityParams memory _rlp;
    _rlp.lpTokenAmt = wp.lpAmtToRemove;
    _rlp.slippage = wp.slippage;
    _rlp.executionFee = wp.executionFee;
    bytes32 _withdrawKey = GMXWorker.removeLiquidity(self, _rlp);

    return _withdrawKey;
  }

  /**
    * @dev Swap tokens in this vault
    * @param self Vault store data
    * @param sp GMXTypes.SwapParams struct
    * @return swapKey Swap order key
  */
  function swap(
    GMXTypes.Store storage self,
    GMXTypes.SwapParams memory sp
  ) external returns (bytes32) {
    return GMXWorker.swap(self, sp);
  }

  /**
    * @dev Check if swap between tokens is needed to ensure enough repayment for both tokens
    * @param self Vault store data
    * @param rp GMXTypes.RepayParams struct
    * @return (swapNeeded, tokenFrom, tokenTo, swapFromAmt)
  */
  function swapForRepay(
    GMXTypes.Store storage self,
    GMXTypes.RepayParams memory rp
  ) external view returns (bool, address, address, uint256) {
    address _tokenFrom;
    address _tokenTo;
    uint256 _tokenFromAmt;
    uint256 _tokenToAmt;

    if (rp.repayTokenAAmt > self.tokenA.balanceOf(address(this))) {
      // If more tokenA is needed for repayment
      _tokenToAmt = rp.repayTokenAAmt - self.tokenA.balanceOf(address(this));
      _tokenFrom = address(self.tokenB);
      _tokenTo = address(self.tokenA);
    } else if (rp.repayTokenBAmt > self.tokenB.balanceOf(address(this))) {
      // If more tokenB is needed for repayment
      _tokenToAmt = rp.repayTokenBAmt - self.tokenB.balanceOf(address(this));
      _tokenFrom = address(self.tokenA);
      _tokenTo = address(self.tokenB);
    } else {
      // If more there is enough to repay both tokens
      return (false, address(0), address(0), 0);
    }

    // Get estimated amounts to swap tokenFrom for desired amount of tokenTo
    _tokenFromAmt = self.gmxOracle.getAmountsIn(
      address(self.lpToken), // marketToken
      address(self.tokenA), // indexToken
      address(self.tokenA), // longToken
      address(self.tokenB), // shortToken
      _tokenTo, // _tokenTo
      _tokenToAmt // amountsOut of _tokenTo wanted
    );

    if (_tokenFromAmt > 0) {
      return (true, _tokenFrom, _tokenTo, _tokenFromAmt);
    } else {
      return (false, address(0), address(0), 0);
    }
  }

  // /**
  //   * @dev Compound ERC20 token rewards, convert to more LP
  //   * @notice keeper will call compound with different ERC20 reward tokens received by vault
  //   * @param self Vault store data
  //   * @param token Address of token to swap from
  //   * @param slippage Slippage tolerance for minimum amount to receive; e.g. 3 = 0.03%
  //   * @param deadline Timestamp of deadline for swap to go through
  // */
  // function compound(
  //   GMXTypes.Store storage self,
  //   address token,
  //   uint256 slippage,
  //   uint256 deadline
  // ) external {
  //   IERC20(token).approve(address(self.router), IERC20(token).balanceOf(address(this)));

  //   GMXWorker.swap(
  //     self,
  //     token,
  //     address(self.tokenB),
  //     IERC20(token).balanceOf(address(this)),
  //     slippage,
  //     deadline
  //   );

  //   // Clip vault strategy fee
  //   uint256 _fee = self.tokenB.balanceOf(address(this))
  //                 * self.performanceFee
  //                 / SAFE_MULTIPLIER;

  //   self.tokenB.safeTransfer(self.treasury, _fee);

  //   // Add liquidity and stake
  //   GMXWorker.swapForOptimalDeposit(self, slippage, deadline);
  //   GMXWorker.addLiquidity(self, slippage, deadline);
  //   GMXWorker.stake(self, self.lpToken.balanceOf(address(this)));
  // }


  /**
    * @dev Unstakes and withdraws all LP tokens, repay all debts to lending
    * vaults and leaving assets in vault for depositors to withdraw
    * @param self Vault store data
    * @param slippage Slippage tolerance for minimum amount to receive; e.g. 3 = 0.03%
    * @param deadline Timestamp of deadline for swap to go through
  */
  function emergencyShutdown(
    GMXTypes.Store storage self,
    uint256 slippage,
    uint256 deadline
  ) external {
    // uint256 lpAmt_ = GMXReader.lpAmt(self);

    // removeLiquidityAndRepay(self, lpAmt_, slippage, deadline);
  }

  /**
    * @dev Borrow assets again and re-add liquidity using all available assets and restake
    * @param self Vault store data
    * @param slippage Slippage tolerance for minimum amount to receive; e.g. 3 = 0.03%
    * @param deadline Timestamp of deadline for swap to go through
  */
  function emergencyResume(
    GMXTypes.Store storage self,
    uint256 slippage,
    uint256 deadline
  ) external {
    // // Get the "equity value" which is tokenA + tokenB value in the vault
    // uint256 _valueOfAssetsInVault =
    //   GMXReader.convertToUsdValue(
    //     self,
    //     address(self.tokenA),
    //     10**(IERC20Metadata(address(self.tokenA)).decimals())
    //   )
    //   +
    //   GMXReader.convertToUsdValue(
    //     self,
    //     address(self.tokenB),
    //     10**(IERC20Metadata(address(self.tokenB)).decimals())
    //   );

    // borrowAndAddLiquidity(self, _valueOfAssetsInVault, slippage, deadline);
  }

  /**
    * @dev Calculate how much tokens to borrow
    * @param self Vault store data
    * @param depositValue Deposit value in 1e18
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
}

