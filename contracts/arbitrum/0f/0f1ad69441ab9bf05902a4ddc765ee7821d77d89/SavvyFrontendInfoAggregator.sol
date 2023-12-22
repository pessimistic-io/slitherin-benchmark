// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./Ownable2StepUpgradeable.sol";
import "./EnumerableSet.sol";

import "./IInfoAggregator.sol";
import "./ISavvyPriceFeed.sol";
import "./IVeSvy.sol";
import "./ISavvyToken.sol";
import "./ISavvyBooster.sol";
import "./ISavvySwap.sol";

import "./Checker.sol";
import {InfoAggregatorUtils} from "./InfoAggregatorUtils.sol";

contract SavvyFrontendInfoAggregator is
    Ownable2StepUpgradeable,
    ISavvyFrontend
{
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Address of InfoAggregator.
    IInfoAggregator public infoAggregator;

    /// @dev Addresses of SavvySwap.
    EnumerableSet.AddressSet private savvySwaps;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        IInfoAggregator infoAggregator_,
        address[] memory savvySwaps_
    ) public initializer {
        Checker.checkArgument(
            address(infoAggregator_) != address(0),
            "zero infoAggregator address"
        );
        infoAggregator = infoAggregator_;
        uint256 length = savvySwaps_.length;
        for (uint256 i = 0; i < length; i++) {
            address savvySwap_ = savvySwaps_[i];
            Checker.checkArgument(
                savvySwap_ != address(0),
                "SavvySwap address cannot be zero"
            );
            Checker.checkArgument(
                !savvySwaps.contains(savvySwap_),
                "SavvySwap already exists"
            );
            savvySwaps.add(savvySwap_);
        }
        __Ownable_init();
    }

    /// @inheritdoc ISavvyFrontend
    function setInfoAggregator(
        address infoAggregator_
    ) external override onlyOwner {
        Checker.checkArgument(
            address(infoAggregator_) != address(0),
            "zero infoAggregator address"
        );
        infoAggregator = IInfoAggregator(infoAggregator_);
    }

    /// @inheritdoc	ISavvyFrontend
    function setSavvySwap(
        address[] memory savvySwaps_,
        bool[] memory shouldAdd_
    ) external override onlyOwner {
        Checker.checkArgument(
            savvySwaps_.length == shouldAdd_.length,
            "SavvySwaps and ShouldAdd need to have the same length."
        );
        uint256 length = savvySwaps_.length;
        Checker.checkArgument(length > 0, "empty SavvySwaps array");

        for (uint256 i = 0; i < length; i++) {
            address savvySwap = savvySwaps_[i];
            Checker.checkArgument(
                savvySwap != address(0),
                "zero SavvySwaps address"
            );
            if (shouldAdd_[i]) {
                Checker.checkArgument(
                    savvySwaps.contains(savvySwap) == false,
                    "SavvySwap already exists"
                );
                savvySwaps.add(savvySwap);
            } else {
                savvySwaps.remove(savvySwap);
            }
        }
    }

    function getSavvySwaps()
        external
        view
        onlyOwner
        returns (address[] memory)
    {
        return savvySwaps.values();
    }

    /// @inheritdoc ISavvyFrontend
    function getDashboardPageInfo(
        address account_
    ) external view override returns (DashboardPageInfo memory) {
        return
            InfoAggregatorUtils._getDashboardPageInfo(
                infoAggregator.getSavvyPositionManagers(),
                account_,
                infoAggregator.svyPriceFeed()
            );
    }

    /// @inheritdoc ISavvyFrontend
    function getPoolsPageInfo(
        address account_
    ) external view override returns (PoolsPageInfo memory) {
        Checker.checkArgument(account_ != address(0), "zero account address");

        address[] memory savvyPositionManagers = infoAggregator
            .getSavvyPositionManagers();
        ISavvyPriceFeed svyPriceFeed = infoAggregator.svyPriceFeed();
        FullPoolInfo[] memory poolsInfo = InfoAggregatorUtils._getPoolsInfo(
            svyPriceFeed,
            savvyPositionManagers,
            account_
        );
        DashboardPageInfo memory dashboardPageInfo = InfoAggregatorUtils
            ._getDashboardPageInfo(
                savvyPositionManagers,
                account_,
                svyPriceFeed
            );
        return
            PoolsPageInfo(
                poolsInfo,
                dashboardPageInfo.debtTokens,
                dashboardPageInfo.availableDeposit,
                dashboardPageInfo.availableCredit,
                dashboardPageInfo.outstandingDebt
            );
    }

    /// @inheritdoc ISavvyFrontend
    function getMySVYPageInfo(
        address account_
    ) external view override returns (MySVYPageInfo memory) {
        Checker.checkArgument(account_ != address(0), "zero account address");

        ISavvyToken svyToken = infoAggregator.svyToken();
        IVeSvy veSvy = infoAggregator.veSvy();
        ISavvyBooster svyBooster = infoAggregator.svyBooster();
        return
            MySVYPageInfo(
                svyToken.balanceOf(account_), //svyBalance
                veSvy.getStakedSvy(account_), //stakedSVYBalance
                svyBooster.getClaimableRewards(account_), //claimableSVY
                svyBooster.getSvyEarnRate(account_), //svyEarnRatePerSec
                veSvy.balanceOf(account_), //veSVYBalance
                veSvy.claimable(account_), //claimableVeSVY
                veSvy.getVeSVYEarnRatePerSec(account_), //veSVYEarnRatePerSec
                veSvy.getMaxVeSVYEarnable(account_) //maxSvyEarnable
            );
    }

    /// @inheritdoc ISavvyFrontend
    function getSwapPageInfo(
        address account_
    ) external view override returns (SwapPageInfo memory) {
        Checker.checkArgument(account_ != address(0), "zero account address");

        uint256 length = savvySwaps.length();
        SwapInfo[] memory swapInfos = new SwapInfo[](length);

        for (uint256 i = 0; i < length; i++) {
            ISavvySwap savvySwap = ISavvySwap(savvySwaps.at(i));
            IERC20 depositToken = IERC20(savvySwap.syntheticToken());
            swapInfos[i] = SwapInfo(
                address(savvySwap), // savvySwap
                address(depositToken), // depositToken
                savvySwap.baseToken(), // swapTargetToken
                depositToken.balanceOf(account_), // availableDepositAmount
                savvySwap.getUnswappedBalance(account_), // depositedAmount
                savvySwap.getClaimableBalance(account_) *
                    savvySwap.conversionFactor() // claimableAmount
            );
        }

        return SwapPageInfo(swapInfos);
    }
}

