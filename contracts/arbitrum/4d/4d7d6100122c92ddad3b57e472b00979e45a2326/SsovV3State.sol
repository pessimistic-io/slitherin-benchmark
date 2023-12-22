//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";

contract SsovV3State {
    /// @dev Underlying assets symbol
    string public underlyingSymbol;

    /// @notice Whether this is a Put or Call SSOV
    bool public isPut;

    /// @dev Contract addresses
    Addresses public addresses;

    /// @dev Collateral Token
    IERC20 public collateralToken;

    /// @dev Current epoch for ssov
    uint256 public currentEpoch;

    /// @dev Expire delay tolerance
    uint256 public expireDelayTolerance = 5 minutes;

    /// @dev The precision of the collateral token
    uint256 public collateralPrecision;

    /// @dev epoch => EpochData
    mapping(uint256 => EpochData) public epochData;

    /// @dev Mapping of (epoch => (strike => EpochStrikeData))
    mapping(uint256 => mapping(uint256 => EpochStrikeData))
        public epochStrikeData;

    /// @dev tokenId => WritePosition
    mapping(uint256 => WritePosition) internal writePositions;

    /*==== STRUCTS ====*/

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
        uint256 startTime;
        uint256 expiry;
        uint256 settlementPrice;
        uint256 totalCollateralBalance; // Premium + Deposits from all strikes
        uint256 collateralExchangeRate; // Exchange rate for collateral to underlying
        uint256[] totalRewardsCollected;
        uint256[] rewardDistributionRatios;
        address[] rewardTokensToDistribute;
        uint256[] strikes;
        bool expired;
    }

    struct EpochStrikeData {
        /// Address of the strike token
        address strikeToken;
        /// Last checkpoint for the vault for an epoch for a strike
        VaultCheckpoint lastVaultCheckpoint;
        uint256[] rewardsStoredForPremiums;
        uint256[] rewardsDistributionRatiosForPremiums;
    }

    struct VaultCheckpoint {
        uint256 premiumCollectedCumulative;
        uint256 activeCollateral;
        uint256 totalCollateral;
        uint256 activeCollateralRatio;
        uint256 premiumDistributionRatio;
        uint256[] rewardDistributionRatios;
    }

    struct WritePosition {
        uint256 epoch;
        uint256 strike;
        uint256 collateralAmount;
        VaultCheckpoint vaultCheckpoint;
    }

    /*==== ERRORS ====*/

    event ExpireDelayToleranceUpdate(uint256 expireDelayTolerance);

    event AddressesSet(Addresses addresses);

    event EmergencyWithdraw(address sender);

    event EpochExpired(address sender, uint256 settlementPrice);

    event Bootstrap(uint256 epoch, uint256[] strikes);

    event Deposit(uint256 tokenId, address user, address sender);

    event Purchase(
        uint256 epoch,
        uint256 strike,
        uint256 amount,
        uint256 premium,
        uint256 fee,
        address indexed user,
        address sender
    );

    event Settle(
        uint256 epoch,
        uint256 strike,
        uint256 amount,
        uint256 pnl, // pnl transfered to the user
        uint256 fee, // fee sent to fee distributor
        address indexed user
    );

    event Withdraw(
        uint256 tokenId,
        uint256 collateralTokenWithdrawn,
        uint256[] rewardTokenWithdrawAmounts,
        address indexed to,
        address sender
    );
}

