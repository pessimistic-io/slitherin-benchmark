// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { GMXTypes } from "./GMXTypes.sol";
import { GMXReader } from "./GMXReader.sol";
import { GMXChecks } from "./GMXChecks.sol";
import { GMXManager } from "./GMXManager.sol";

library GMXWithdraw {
  using SafeERC20 for IERC20;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

  /* ========== EVENTS ========== */

  event WithdrawCreated(address indexed user, uint256 shareAmt);
  event WithdrawCompleted(
    address indexed user,
    address token,
    uint256 tokenAmt
  );

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * @dev Withdraws asset from vault, burns svToken from user
    * @param self Vault store data
    * @param wp WithdrawParams struct of withdraw parameters
  */
  function withdraw(
    GMXTypes.Store storage self,
    GMXTypes.WithdrawParams memory wp
  ) external {
    uint256 _shareRatio = wp.shareAmt
      * SAFE_MULTIPLIER
      / IERC20(address(self.vault)).totalSupply();

    wp.lpAmtToRemove = _shareRatio
      * GMXReader.lpAmt(self)
      / SAFE_MULTIPLIER;

    GMXTypes.HealthParams memory _hp;
    _hp.equityBefore = GMXReader.equityValue(self);
    _hp.lpAmtBefore = GMXReader.lpAmt(self);
    _hp.debtRatioBefore = GMXReader.debtRatio(self);
    _hp.deltaBefore = GMXReader.delta(self);

    GMXTypes.RepayParams memory _rp;
    _rp.repayTokenAAmt = 0;
    _rp.repayTokenBAmt = 0;

    GMXTypes.WithdrawCache memory _wc;
    _wc.user = payable(msg.sender);
    _wc.timestamp = block.timestamp;
    _wc.shareRatio = _shareRatio;
    _wc.withdrawParams = wp;
    _wc.healthParams = _hp;
    _wc.repayParams = _rp;

    self.withdrawCache = _wc;

    GMXChecks.beforeWithdrawChecks(self);

    self.status = GMXTypes.Status.Withdraw;

    self.vault.mintMgmtFee();

    self.status = GMXTypes.Status.Remove_Liquidity;

    bytes32 _withdrawKey = GMXManager.removeLiquidity(
      self,
      _wc.withdrawParams
    );

    _wc.withdrawKey = _withdrawKey;

    // Add withdrawKey to store
    self.withdrawCache = _wc;

    self.status = GMXTypes.Status.Swap_For_Repay;

    emit WithdrawCreated(
      _wc.user,
      _wc.withdrawParams.shareAmt
    );
  }

  /**
    * @dev Determine if swap is required for repayment after withdrawal of LP
    * @notice Called by keeper via Event Emitted from GMX
    * @param self Vault store data
    * @param withdrawKey Withdraw key hash to find withdrawal info
  */
  function processSwapForRepay(
    GMXTypes.Store storage self,
    bytes32 withdrawKey
  ) external {
    GMXChecks.processSwapForRepayChecks(self, withdrawKey);

    GMXTypes.WithdrawCache memory _wc = self.withdrawCache;

    (
      uint256 _repayTokenAAmt,
      uint256 _repayTokenBAmt
    ) = GMXManager.calcRepay(self, _wc.shareRatio);

    _wc.repayParams.repayTokenAAmt = _repayTokenAAmt;
    _wc.repayParams.repayTokenBAmt = _repayTokenBAmt;

    // Check if swap between assets are needed for repayment
    (
      bool _swapNeeded,
      address _tokenFrom,
      address _tokenTo,
      uint256 _tokenFromAmt
    ) = GMXManager.swapForRepay(self, _wc.repayParams);

    _wc.withdrawParams.swapForRepayParams.tokenFrom = _tokenFrom;
    _wc.withdrawParams.swapForRepayParams.tokenTo = _tokenTo;
    _wc.withdrawParams.swapForRepayParams.tokenFromAmt = _tokenFromAmt;

    if (_swapNeeded) {
      // A swap is needed to repay tokens properly
      bytes32 _orderKey = GMXManager.swap(self, _wc.withdrawParams.swapForRepayParams);
      // add swap key to track swap order for this withdrawal repayment
      // self.vault.addSwapKeyToWithdrawKey(_swapKey, withdrawKey);
      _wc.withdrawParams.swapForRepayParams.orderKey = _orderKey;

      self.withdrawCache = _wc;

      self.status = GMXTypes.Status.Repay;

      // Note keeper will monitor for when swap completes and call processRepay()
    } else {
      // No swaps needed for repayment so proceed to process repay immediately
      self.withdrawCache = _wc;

      self.status = GMXTypes.Status.Repay;

      processRepay(self, withdrawKey, bytes32(0));
    }
  }

  /**
    * @dev Repay debt and check if swap for withdrawal is needed
    * @notice Called by keeper via Event Emitted from GMX
    * @notice orderKey can be bytes32(0) if there is no swap needed for repay
    * @param self Vault store data
    * @param withdrawKey Withdraw key hash to find withdrawal info
    * @param orderKey Swap key hash to find withdrawKey hash
  */
  function processRepay(
    GMXTypes.Store storage self,
    bytes32 withdrawKey,
    bytes32 orderKey
  ) public {
    GMXChecks.processRepayChecks(self, withdrawKey, orderKey);

    GMXTypes.WithdrawCache memory _wc = self.withdrawCache;

    // Repay debt
    GMXManager.repay(
      self,
      _wc.repayParams.repayTokenAAmt,
      _wc.repayParams.repayTokenBAmt
    );

    // Get state of vault after
    _wc.healthParams.equityAfter = GMXReader.equityValue(self);

    self.withdrawCache = _wc;

    self.status = GMXTypes.Status.Swap_For_Withdraw;

    processSwapForWithdraw(self, withdrawKey);
  }

  /**
    * @dev Check if swap for withdrawal is needed and execute swap if so
    * @notice Called by keeper via Event Emitted from GMX
    * @param self Vault store data
    * @param withdrawKey Withdraw key hash to find withdrawal info
  */
  function processSwapForWithdraw(
    GMXTypes.Store storage self,
    bytes32 withdrawKey
  ) public {
    GMXChecks.processSwapForWithdrawChecks(self, withdrawKey);

    GMXTypes.WithdrawCache memory _wc = self.withdrawCache;

    if (_wc.withdrawParams.token == address(self.lpToken)) {
      // TODO handling of withdrawal in LP tokens
      // which doesnt need anby swaps
      self.status = GMXTypes.Status.Withdraw;

      processBurn(self, withdrawKey, bytes32(0));
    }

    GMXTypes.SwapParams memory _sp =
      _wc.withdrawParams.swapForWithdrawParams;

    if (_wc.withdrawParams.token == address(self.tokenA)) {
      _sp.tokenFrom = address(self.tokenB);
      _sp.tokenTo = address(self.tokenA);
      _sp.tokenFromAmt =
        self.tokenB.balanceOf(address(this));
    } else if (_wc.withdrawParams.token == address(self.tokenB)) {
      _sp.tokenFrom = address(self.tokenA);
      _sp.tokenTo = address(self.tokenB);
      _sp.tokenFromAmt =
        self.tokenA.balanceOf(address(this));
    }

    bytes32 _orderKey = GMXManager.swap(
      self,
      _sp
    );

    _wc.withdrawParams.swapForWithdrawParams.orderKey = _orderKey;

    self.withdrawCache = _wc;

    self.status = GMXTypes.Status.Burn;
  }

  /**
    * @dev Process burning of shares and sending of assets to user after swap for withdraw
    * @notice Called by keeper via Event Emitted from GMX
    * @notice orderKey can be bytes32(0) if there is no swap needed for repay
    * @param self Vault store data
    * @param withdrawKey Withdraw key hash to find withdrawal info
    * @param orderKey Swap key hash to find withdrawKey hash
  */
  function processBurn(
    GMXTypes.Store storage self,
    bytes32 withdrawKey,
    bytes32 orderKey
  ) public {
    GMXChecks.processBurnChecks(self, withdrawKey, orderKey);

    GMXTypes.WithdrawCache memory _wc = self.withdrawCache;

    IERC20 withdrawToken = IERC20(_wc.withdrawParams.token);

    // TODO this wont work for lpToken
    _wc.withdrawTokenAmt = withdrawToken.balanceOf(address(this));

    // Transfer requested withdraw asset to user
    withdrawToken.safeTransfer(
      _wc.user,
      withdrawToken.balanceOf(address(this)) // TODO this wont work for lptoken
    );

    // Burn user shares
    self.vault.burn(_wc.user, _wc.withdrawParams.shareAmt);

    self.withdrawCache = _wc;

    GMXChecks.afterWithdrawChecks(self);

    self.status = GMXTypes.Status.Open;

    emit WithdrawCompleted(
      _wc.user,
      _wc.withdrawParams.token,
      _wc.withdrawTokenAmt
    );
  }
}

