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

    struct EpochData {
        bool expired;
        uint256 startTime;
        uint256 expiry;
        uint256 settlementPrice;
        uint256 totalCollateralBalance; // Premium + Deposits from all strikes
        uint256 collateralExchangeRate; // Exchange rate for collateral to underlying
        uint256[] strikes;
        uint256[] totalRewardsCollected;
        uint256[] rewardDistributionRatios;
        address[] rewardTokensToDistribute;
    }

    struct EpochStrikeData {
        address strikeToken;
        uint256 totalCollateral;
        uint256 activeCollateral;
        uint256 totalPremiums;
        uint256 checkpointPointer;
        uint256[] rewardStoredForPremiums;
        uint256[] rewardDistributionRatiosForPremiums;
    }

    struct VaultCheckpoint {
        uint256 startTime;
        uint256 activeCollateral;
        uint256 totalCollateral;
        uint256 accruedPremium;
    }

    function isPut() external view returns (bool);

    function currentEpoch() external view returns (uint256);

    function collateralPrecision() external view returns (uint256);

    function addresses() external view returns (Addresses memory);

    function collateralToken() external view returns (IERC20);

    function getCheckpoints(uint256 epoch, uint256 strike)
        external
        view
        returns (VaultCheckpoint[] memory);

    function deposit(
        uint256 strikeIndex,
        uint256 amount,
        address to
    ) external returns (uint256 tokenId);

    function purchase(
        uint256 strikeIndex,
        uint256 amount,
        address to
    ) external returns (uint256 premium, uint256 totalFee);

    function settle(
        uint256 strikeIndex,
        uint256 amount,
        uint256 epoch,
        address to
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
            uint256 checkpointIndex,
            uint256[] memory rewardDistributionRatios
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

