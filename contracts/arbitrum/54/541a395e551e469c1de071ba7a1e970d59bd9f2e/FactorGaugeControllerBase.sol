// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./SafeERC20.sol";
import "./EnumerableSet.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

import "./IFactorGaugeController.sol";
import "./IEscrowedFactorToken.sol";

import "./Helpers.sol";

/**
 * @notice FactorGaugeControllerBase.sol is a modified version of Pendle's PendleGaugeControllerBaseUpg.sol:
 * https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts
   /LiquidityMining/GaugeController/PendleGaugeControllerBaseUpg.sol
 * 
 * @dev Gauge controller provides no write function to any party other than voting controller
 * @dev Gauge controller will receive (lpTokens[], fctr per sec[]) from voting controller and
 * set it directly to contract state
 * @dev All of the core data in this function are set to private to prevent unintended assignments
 * on inheriting contracts
 */

abstract contract FactorGaugeControllerBase is IFactorGaugeController, OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // =============================================================
    //                          Errors
    // =============================================================

    // GENERIC MSG
    error ArrayLengthMismatch();
    error GCNotActiveVault(address vault);

    struct VaultRewardData {
        uint128 fctrPerSec;
        uint128 accumulatedFctr;
        uint128 lastUpdated;
        uint128 incentiveEndsAt;
    }

    struct GaugeControllerBaseStorage {
        address esFctr;
        mapping(address => VaultRewardData) rewardData;
        mapping(uint128 => bool) epochRewardReceived;
        EnumerableSet.AddressSet allActiveVaults;
    }

    bytes32 private constant GAUGE_CONTROLLER_BASE_STORAGE = keccak256('factor.gauge.controller.base.storage');

    function _getGaugeControllerBaseStorage() internal pure returns (GaugeControllerBaseStorage storage ds) {
        bytes32 slot = GAUGE_CONTROLLER_BASE_STORAGE;
        assembly {
            ds.slot := slot
        }
    }

    uint128 internal constant WEEK = 1 weeks;

    function __FactorGaugeControllerBase_init(address _esFctr) internal onlyInitializing {
        _getGaugeControllerBaseStorage().esFctr = _esFctr;
    }

    /**
     * @notice add a vault to allow vaults to redeem rewards. Can only be done by governance
     */

    function addVault(address _vault) external onlyOwner {
        GaugeControllerBaseStorage storage $ = _getGaugeControllerBaseStorage();

        if (!$.allActiveVaults.add(_vault)) assert(false);

        emit AddVault(_vault);
    }

    /**
     * @notice remove a vault from redeeming rewards. Can only be done by governance
     */

    function removeVault(address _vault) external onlyOwner {
        if (!_isVaultActive(_vault)) revert GCNotActiveVault(_vault);

        GaugeControllerBaseStorage storage $ = _getGaugeControllerBaseStorage();

        if (!$.allActiveVaults.remove(_vault)) assert(false);

        emit RemoveVault(_vault);
    }

    /**
     * @notice claim the rewards allocated by gaugeController
     * @dev only active vault wrapper can call this
     */
    function redeemVaultReward() external {
        address vault = msg.sender;

        if (!_isVaultActive(vault)) revert GCNotActiveVault(vault);

        GaugeControllerBaseStorage storage $ = _getGaugeControllerBaseStorage();

        $.rewardData[vault] = _getUpdatedVaultReward(vault);

        uint256 amount = $.rewardData[vault].accumulatedFctr;

        if (amount != 0) {
            $.rewardData[vault].accumulatedFctr = 0;
            IERC20($.esFctr).safeTransfer(vault, amount);
        }

        emit VaultClaimReward(vault, amount);
    }

    function fundEsFctr(uint256 amount) external {
        IERC20(_getGaugeControllerBaseStorage().esFctr).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawEsFctr(uint256 amount) external onlyOwner {
        IERC20(_getGaugeControllerBaseStorage().esFctr).safeTransfer(msg.sender, amount);
    }

    function esFctr() external view returns (address) {
        return _getGaugeControllerBaseStorage().esFctr;
    }

    function rewardData(address vault) external view returns (uint128 fctrPerSec, uint128, uint128, uint128) {
        VaultRewardData memory rwd = _getGaugeControllerBaseStorage().rewardData[vault];
        return (rwd.fctrPerSec, rwd.accumulatedFctr, rwd.lastUpdated, rwd.incentiveEndsAt);
    }

    function epochRewardReceived(uint128 wTime) external view returns (bool) {
        return _getGaugeControllerBaseStorage().epochRewardReceived[wTime];
    }

    function getAllActiveVaults() external view returns (address[] memory) {
        return _getGaugeControllerBaseStorage().allActiveVaults.values();
    }

    function isVaultActive(address vault) external view returns (bool) {
        return _isVaultActive(vault);
    }

    /**
     * @notice receive voting results from FactorScale. Only the first message for a timestamp
     * will be accepted, all subsequent messages will be ignored
     */
    function _receiveVotingResults(uint128 wTime, address[] memory vaults, uint256[] memory fctrAmounts) internal {
        if (vaults.length != fctrAmounts.length) revert ArrayLengthMismatch();

        GaugeControllerBaseStorage storage $ = _getGaugeControllerBaseStorage();

        // only accept the first message for the wTime
        if ($.epochRewardReceived[wTime]) return;
        $.epochRewardReceived[wTime] = true;

        uint256 totalEsFactor = 0;

        for (uint256 i = 0; i < vaults.length; ++i) {
            require(fctrAmounts[i] <= type(uint128).max); // cast uint256 to uint128

            totalEsFactor += fctrAmounts[i];

            _addRewardsToVault(vaults[i], uint128(fctrAmounts[i]));
        }

        IEscrowedFactorToken($.esFctr).mint(address(this), totalEsFactor);

        emit ReceiveVotingResults(wTime, vaults, fctrAmounts);
    }

    /**
     * @notice merge the additional rewards with the existing rewards
     * @dev this function will calc the total amount of Fctr that hasn't been factored into
     * accumulatedFctr yet, combined them with the additional fctrAmount, then divide them
     * equally over the next one week
     */
    function _addRewardsToVault(address vault, uint128 fctrAmount) internal {
        VaultRewardData memory rwd = _getUpdatedVaultReward(vault);
        uint128 leftover = (rwd.incentiveEndsAt - rwd.lastUpdated) * rwd.fctrPerSec;
        uint128 newSpeed = (leftover + fctrAmount) / WEEK;

        _getGaugeControllerBaseStorage().rewardData[vault] = VaultRewardData({
            fctrPerSec: newSpeed,
            accumulatedFctr: rwd.accumulatedFctr,
            lastUpdated: uint128(block.timestamp),
            incentiveEndsAt: uint128(block.timestamp) + WEEK
        });

        emit UpdateVaultReward(vault, newSpeed, uint128(block.timestamp) + WEEK);
    }

    /**
     * @notice get the updated state of the vault, to the current time with all the undistributed
     * Fctr distributed to the accumulatedFctr
     * @dev expect to update accumulatedFctr & lastUpdated in VaultRewardData
     */
    function _getUpdatedVaultReward(address vault) internal view returns (VaultRewardData memory) {
        VaultRewardData memory rwd = _getGaugeControllerBaseStorage().rewardData[vault];

        uint128 newLastUpdated = uint128(
            uint128(block.timestamp) < rwd.incentiveEndsAt ? uint128(block.timestamp) : rwd.incentiveEndsAt
        );
        rwd.accumulatedFctr += rwd.fctrPerSec * (newLastUpdated - rwd.lastUpdated);
        rwd.lastUpdated = newLastUpdated;
        return rwd;
    }

    function _isVaultActive(address vault) internal view returns (bool) {
        return _getGaugeControllerBaseStorage().allActiveVaults.contains(vault);
    }
}

