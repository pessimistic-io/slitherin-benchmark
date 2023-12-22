// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IGMXDeposit } from "./IGMXDeposit.sol";
import { IGMXWithdrawal } from "./IGMXWithdrawal.sol";
import { IGMXEvent } from "./IGMXEvent.sol";
import { IGMXOrder } from "./IGMXOrder.sol";
import { GMXTypes } from "./GMXTypes.sol";
import { GMXReader } from "./GMXReader.sol";
import { GMXChecks } from "./GMXChecks.sol";
import { GMXManager } from "./GMXManager.sol";

library GMXDeposit {
  using SafeERC20 for IERC20;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

  /* ========== EVENTS ========== */

  event DepositCreated(
    address indexed user,
    address asset,
    uint256 assetAmt
  );
  event DepositCompleted(
    address indexed user,
    uint256 shareAmt,
    uint256 equityBefore,
    uint256 equityAfter
  );

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
    * @dev Deposits native asset into vault and mint svToken to user
    * @param self Vault store data
    * @param dp DepositParams struct of deposit parameters
  */
  function depositERC20(
    GMXTypes.Store storage self,
    GMXTypes.DepositParams memory dp
  ) external {
    IERC20(dp.token).safeTransferFrom(msg.sender, address(this), dp.amt);

    _deposit(self, dp);
  }

  /**
    * @dev Deposits native asset into vault and mint svToken to user
    * @param self Vault store data
    * @param dp DepositParams struct
  */
  function depositNative(
    GMXTypes.Store storage self,
    GMXTypes.DepositParams memory dp
  ) external {
    GMXChecks.beforeNativeDepositChecks(self, dp);

    self.WNT.deposit{ value: dp.amt }();

    _deposit(self, dp);
  }

  /**
    * @dev Mint shares after deposit is executed on GMX
    * @notice Called after _deposit()
    * @param self Vault store data
    * @param depositKey Deposit key hash to find deposit info
  */
  function processMint(
    GMXTypes.Store storage self,
    bytes32 depositKey
  ) external {
    self.processMint = true; // TEMP

    GMXChecks.processMintChecks(self, depositKey);

    self.processMint2 = true; // TEMP

    GMXTypes.DepositCache memory _dc = self.depositCache;

    _dc.healthParams.equityAfter = GMXReader.equityValue(self);

    // Calculate shares to mint to user based on equity change
    _dc.sharesToUser = GMXReader.valueToShares(
      self,
      _dc.healthParams.equityAfter - _dc.healthParams.equityBefore,
      _dc.healthParams.equityBefore
    );

    self.depositCache = _dc;

    self.processMint3 = true; // TEMP

    GMXChecks.afterDepositChecks(self);

    self.processMint4 = true; // TEMP

    // Mint shares to depositor
    self.vault.mint(
      _dc.user,
      _dc.sharesToUser
    );

    self.processMint5 = true; // TEMP

    // Refund any left over execution fees to user
    self.WNT.withdraw(self.WNT.balanceOf(address(this)));
    (bool success, ) = _dc.user.call{value: address(this).balance}("");
    require(success, "Transfer failed.");

    self.processMint6 = true; // TEMP


    // Clear user deposit data in mapping
    delete self.depositCache;

    self.status = GMXTypes.Status.Open;

    emit DepositCompleted(
      _dc.user,
      _dc.sharesToUser,
      _dc.healthParams.equityBefore,
      _dc.healthParams.equityAfter
    );
  }

  /* ========== INTERNAL FUNCTIONS ========== */


  /**
    * @dev Deposits ERC20 asset into vault and mint svToken to user
    * @notice processMint() to be called after this
    * @param self Vault store data
    * @param dp DepositParams struct of deposit parameter
  */
  function _deposit(
    GMXTypes.Store storage self,
    GMXTypes.DepositParams memory dp
  ) internal {
    GMXTypes.HealthParams memory _hp;
    _hp.equityBefore = GMXReader.equityValue(self);
    _hp.lpAmtBefore = GMXReader.lpAmt(self);
    _hp.debtRatioBefore = GMXReader.debtRatio(self);
    _hp.deltaBefore = GMXReader.delta(self);

    GMXTypes.DepositCache memory _dc;
    _dc.user = msg.sender;
    _dc.timestamp = block.timestamp;
    _dc.depositValue = GMXReader.convertToUsdValue(
      self,
      dp.token,
      dp.amt
    );
    _dc.depositParams = dp;
    _dc.healthParams = _hp;

    self.depositCache = _dc;

    GMXChecks.beforeDepositChecks(self);

    self.status = GMXTypes.Status.Deposit;

    self.vault.mintMgmtFee();

    self.status = GMXTypes.Status.Borrow;

    // Borrow assets and create deposit in GMX
    (
      uint256 _borrowTokenAAmt,
      uint256 _borrowTokenBAmt
    ) = GMXManager.calcBorrow(self, _dc.depositValue);

    _dc.borrowParams.borrowTokenAAmt = _borrowTokenAAmt;
    _dc.borrowParams.borrowTokenBAmt = _borrowTokenBAmt;

    GMXManager.borrow(self, _borrowTokenAAmt, _borrowTokenBAmt);

    self.status = GMXTypes.Status.Add_Liquidity;

    bytes32 _depositKey = GMXManager.addLiquidity(
      self,
      _dc.depositParams
    );

    _dc.depositKey = _depositKey;

    self.depositCache = _dc;

    self.lastDepositBlock = block.number;

    self.status = GMXTypes.Status.Mint;

    emit DepositCreated(
      _dc.user,
      _dc.depositParams.token,
      _dc.depositParams.amt
    );
  }
}

