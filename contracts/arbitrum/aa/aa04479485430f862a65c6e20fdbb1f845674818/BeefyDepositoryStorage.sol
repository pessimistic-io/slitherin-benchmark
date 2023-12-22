// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

// import {BeefyVaultV7} from "../../external/beefy/BeefyVaultV7.sol";
import {BeefyWrapper} from "./BeefyWrapper.sol";
import {IUXDController} from "./IUXDController.sol";
import {IDepository} from "./IDepository.sol";
import {IBeefyStrategyAdapter} from "./IBeefyStrategyAdapter.sol";

abstract contract BeefyDepositoryStorage is IDepository {
    // /// @dev Beefy vault address
    // BeefyVaultV7 public vault;

    /// @dev Beefy wrapper
    BeefyWrapper public vaultWrapper;

    /// @dev UXDController address
    IUXDController public controller;

    IBeefyStrategyAdapter public adapter;

    /// @dev The asset backing managed by this depository
    address public assetToken;

    /// @dev The redeemable managed by this depository
    address public redeemable;

    /// @dev The token deposited to the Beefy vault
    address public poolToken;

    /// @dev Max amount of redeemable depository can manage
    uint256 public redeemableSoftCap;

    /// @dev Amount that can be redeemed. In redeemable decimals
    uint256 public redeemableUnderManagement;

    /// @dev Total amount deposited - amount withdrawn. In assetToken decimals
    uint256 public netAssetDeposits;

    /// @dev PnL that has be claimed/withdrawn
    uint256 public realizedPnl;
}

