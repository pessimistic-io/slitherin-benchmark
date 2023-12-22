//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC721Enumerable} from "./IERC721Enumerable.sol";
import {IERC20} from "./IERC20.sol";

/// @title SSOV V3 interface
interface ISsovV3 is IERC721Enumerable {
    struct Addresses {
        address feeStrategy;
        address stakingStrategy;
        address optionPricing;
        address priceOracle;
        address volatilityOracle;
        address feeDistributor;
        address optionsTokenImplementation;
    }

    struct VaultCheckpoint {
        uint256 premiumCollectedCumulative;
        uint256 activeCollateral;
        uint256 totalCollateral;
        uint256 activeCollateralRatio;
        uint256 premiumDistributionRatio;
        uint256[] rewardDistributionRatios;
    }

    struct EpochData {
        uint256 startTime;
        uint256 expiry;
        uint256 settlementPrice;
        uint256 totalCollateralBalance;
        uint256 collateralExchangeRate;
        uint256[] totalRewardsCollected;
        uint256[] rewardDistributionRatios;
        address[] rewardTokensToDistribute;
        uint256[] strikes;
        bool expired;
    }

    struct EpochStrikeData {
        address strikeToken;
        VaultCheckpoint lastVaultCheckpoint;
        uint256[] rewardsStoredForPremiums;
        uint256[] rewardsDistributionRatiosForPremiums;
    }

    function currentEpoch() external returns (uint256);

    function addresses() external returns (Addresses memory);

    function collateralToken() external returns (IERC20);

    function deposit(
        uint256 strikeIndex,
        uint256 amount,
        address user
    ) external returns (uint256 tokenId);

    function purchase(
        uint256 strikeIndex,
        uint256 amount,
        address user
    ) external returns (uint256 premium, uint256 totalFee);

    function settle(
        uint256 strikeIndex,
        uint256 amount,
        uint256 epoch
    ) external returns (uint256 pnl);

    function withdraw(uint256 tokenId, address to)
        external
        returns (
            uint256 collateralTokenWithdrawAmount,
            uint256[] memory rewardTokenWithdrawAmounts
        );

    function getUnderlyingPrice() external view returns (uint256);

    function getCollateralPrice() external view returns (uint256);

    function getVolatility(uint256 _strike) external view returns (uint256);

    function calculatePremium(
        uint256 _strike,
        uint256 _amount,
        uint256 _expiry
    ) external view returns (uint256 premium);

    function calculatePnl(
        uint256 price,
        uint256 strike,
        uint256 amount
    ) external view returns (uint256);

    function calculatePurchaseFees(uint256 strike, uint256 amount)
        external
        view
        returns (uint256);

    function calculateSettlementFees(uint256 pnl)
        external
        view
        returns (uint256);

    function getEpochTimes(uint256 epoch)
        external
        view
        returns (uint256 start, uint256 end);

    function getEpochStrikes(uint256 epoch)
        external
        view
        returns (uint256[] memory);

    function writePosition(uint256 tokenId)
        external
        view
        returns (
            uint256 epoch,
            uint256 strike,
            uint256 collateralAmount,
            VaultCheckpoint memory vaultCheckpoint
        );

    function getEpochData(uint256 epoch)
        external
        view
        returns (EpochData memory);

    function getEpochStrikeData(uint256 epoch, uint256 strike)
        external
        view
        returns (EpochStrikeData memory);
}

