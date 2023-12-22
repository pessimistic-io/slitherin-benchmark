// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

interface IfxKeeperPool {
    struct Pool {
        mapping(address => Deposit) deposits;
        mapping(address => uint256) collateralBalances;
        mapping(uint256 => mapping(uint256 => mapping(address => uint256))) epochToScaleToCollateralToSum;
        uint256 totalDeposits;
        Snapshot snapshot;
        // Forex token loss per unit staked data.
        uint256 fxLossPerUnitStaked;
        uint256 lastErrorFxLossPerUnitStaked;
        mapping(address => uint256) lastErrorCollateralGainRatio;
    }

    struct Snapshot {
        uint256 P;
        uint256 scale;
        uint256 epoch;
    }

    struct Deposit {
        uint256 amount;
        Snapshot snapshot;
        mapping(address => uint256) collateralToSum;
    }

    event Liquidate(
        address indexed account,
        address indexed token,
        uint256 tokenAmount
    );

    event Stake(address indexed account, address indexed token, uint256 amount);

    event Unstake(
        address indexed account,
        address indexed token,
        uint256 amount
    );
    event Withdraw(address indexed account, address indexed token);

    function stake(
        uint256 amount,
        address fxToken,
        address referral
    ) external;

    function unstake(uint256 amount, address fxToken) external;

    function withdrawCollateralReward(address fxToken) external;

    function balanceOfStake(address account, address fxToken)
        external
        view
        returns (uint256 amount);

    function balanceOfRewards(address account, address fxToken)
        external
        view
        returns (
            address[] memory collateralTokens,
            uint256[] memory collateralAmounts
        );

    function shareOf(address account, address fxToken)
        external
        view
        returns (uint256 share);

    function liquidate(address account, address fxToken) external;

    function getPoolCollateralBalance(address fxToken, address collateral)
        external
        view
        returns (uint256 amount);

    function getPoolTotalDeposit(address fxToken)
        external
        view
        returns (uint256 amount);

    function setProtocolFee(uint256 ratio) external;

    function protocolFee() external view returns (uint256);
}

