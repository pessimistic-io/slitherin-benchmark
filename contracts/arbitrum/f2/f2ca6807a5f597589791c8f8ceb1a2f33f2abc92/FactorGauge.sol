// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Initializable } from "./Initializable.sol";
import { Math } from "./Math.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { RewardManager } from "./RewardManager.sol";
import { IVotingEscrow } from "./IVotingEscrow.sol";
import { IFactorGaugeController } from "./IFactorGaugeController.sol";
import { ArrayLib } from "./ArrayLib.sol";

/**
 * @dev FactorGauge.sol is a modified version of Pendle's PendleGauge.sol:
 * https://github.com/pendle-finance/pendle-core-v2-public/blob/main/contracts/core/Market/PendleGauge.sol
 *
 * @notice
 * This is used with FactorVault.
 */
abstract contract FactorGauge is RewardManager, Initializable {
    // =============================================================
    //                         Library
    // =============================================================

    using SafeERC20 for IERC20;
    using Math for uint256;
    using ArrayLib for address[];

    // =============================================================
    //                          Events
    // =============================================================

    event RedeemRewards(address indexed user, uint256[] rewardsOut);

    uint256 internal constant TOKENLESS_PRODUCTION = 40;

    struct FactorGaugeStorage {
        address esFctr;
        address veFctr;
        address gaugeController;
        uint256 totalActiveSupply;
        mapping(address => uint256) activeBalance;
    }

    bytes32 private constant FACTOR_GAUGE_STORAGE = keccak256('factor.base.gauge.storage');

    function _getFactorGaugeStorage() internal pure returns (FactorGaugeStorage storage $) {
        bytes32 slot = FACTOR_GAUGE_STORAGE;
        assembly {
            $.slot := slot
        }
    }

    function __FactorGauge_init(address _veFctr, address _gaugeController) internal onlyInitializing {
        FactorGaugeStorage storage $ = _getFactorGaugeStorage();
        $.veFctr = _veFctr;
        $.gaugeController = _gaugeController;
        $.esFctr = IFactorGaugeController(_gaugeController).esFctr();
    }

    /**
     * @dev Since rewardShares is based on activeBalance, user's activeBalance must be updated AFTER
     * rewards is updated.
     * It's intended to have user's activeBalance updated when rewards is redeemed
     */
    function _redeemRewards(address user) internal virtual returns (uint256[] memory rewardsOut) {
        _updateAndDistributeRewards(user);
        _updateUserActiveBalance(user);
        rewardsOut = _doTransferOutRewards(user, user);
        emit RedeemRewards(user, rewardsOut);
    }

    function _updateUserActiveBalance(address user) internal virtual {
        _updateUserActiveBalanceForTwo(user, address(0));
    }

    function _updateUserActiveBalanceForTwo(address user1, address user2) internal virtual {
        if (user1 != address(0) && user1 != address(this)) _updateUserActiveBalancePrivate(user1);
        if (user2 != address(0) && user2 != address(this)) _updateUserActiveBalancePrivate(user2);
    }

    /**
     * @dev should only be callable from `_updateUserActiveBalanceForTwo` to
     * guarantee user != address(0) && user != address(this)
     */
    function _updateUserActiveBalancePrivate(address user) private {
        assert(user != address(0) && user != address(this));
        
        uint256 lpBalance = _stakedBalance(user);
        uint256 veBoostedLpBalance = _calcVeBoostedLpBalance(user, lpBalance);
        
        uint256 newActiveBalance = Math.min(veBoostedLpBalance, lpBalance);

        FactorGaugeStorage storage $ = _getFactorGaugeStorage();

        $.totalActiveSupply = $.totalActiveSupply - $.activeBalance[user] + newActiveBalance;
        $.activeBalance[user] = newActiveBalance;
    }

    function _calcVeBoostedLpBalance(address user, uint256 lpBalance) internal virtual returns (uint256) {
        FactorGaugeStorage storage $ = _getFactorGaugeStorage();
        (uint256 veFctrSupplyCurrent, uint256 veFctrBalanceCurrent) = IVotingEscrow($.veFctr)
            .totalSupplyAndBalanceCurrent(user);

        // Inspired by Curve's Gauge
        uint256 veBoostedLpBalance = (lpBalance * TOKENLESS_PRODUCTION) / 100;
        if (veFctrSupplyCurrent > 0) {
            veBoostedLpBalance +=
                (((_totalStaked() * veFctrBalanceCurrent) / veFctrSupplyCurrent) * (100 - TOKENLESS_PRODUCTION)) /
                100;
        }
        return veBoostedLpBalance;
    }

    function _redeemExternalReward() internal virtual override {
        IFactorGaugeController(_getFactorGaugeStorage().gaugeController).redeemVaultReward();
    }

    function _stakedBalance(address user) internal view virtual returns (uint256);

    function _totalStaked() internal view virtual returns (uint256);

    function _getRewardTokens() internal view virtual override returns (address[] memory) {
        address[] memory rewardTokens = new address[](0);
        return rewardTokens.append(_getFactorGaugeStorage().esFctr);
    }

    function _rewardSharesTotal() internal view virtual override returns (uint256) {
        return _getFactorGaugeStorage().totalActiveSupply;
    }

    function _rewardSharesUser(address user) internal view virtual override returns (uint256) {
        return _getFactorGaugeStorage().activeBalance[user];
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal virtual {
        _updateAndDistributeRewardsForTwo(from, to);
    }

    function _afterTokenTransfer(address from, address to, uint256) internal virtual {
        _updateUserActiveBalanceForTwo(from, to);
    }

    function totalActiveSupply() public view returns (uint256) {
        return _getFactorGaugeStorage().totalActiveSupply;
    }

    function activeBalance(address user) public view returns (uint256) {
        return _getFactorGaugeStorage().activeBalance[user];
    }

    function _pendingRewards(
        address user
    ) internal view returns (uint256) {
        FactorGaugeStorage storage $ = _getFactorGaugeStorage();

        address rewardToken = $.esFctr;

        (
            uint128 fctrPerSec, 
            uint128 accumulatedFctr, 
            uint128 lastUpdated,
        ) = IFactorGaugeController($.gaugeController).rewardData(address(this));

        accumulatedFctr += fctrPerSec * (uint128(block.timestamp) - lastUpdated);

        return _calculateReward(user, rewardToken, accumulatedFctr);
    }
}

