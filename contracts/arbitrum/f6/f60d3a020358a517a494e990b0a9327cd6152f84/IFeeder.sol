// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IToken.sol";

interface IFeeder {

    struct UserPosition {
        uint256 totalDeposit; // USDT
        uint256 totalWithdrawal; // USDT
        uint256 tokenAmount; // USDT
    }

    struct UserAccruals {
        uint256 deposit; // user pending deposit amount (USDT)
        uint256 withdraw; // user pending withdrawals amount (iTOKEN)

        // TODO: deprecated
        uint256 block; // last period when accruals were made
    }

    struct FundInfo {
        uint256 minDeposit;
        uint256 minWithdrawal;
        uint256 lastPeriod;
        IToken itoken;
        address trade;
    }

    struct FundHwmData {
        bool hwm;
        uint256 hwmValue;
    }

    /**
    * Events
    */
    event NewFund(uint256 fundId, address manager);

    event Deposit(uint256 fundId, address depositedFrom, uint256 amount);
    event DepositCancelled(uint256 fundId, address indexed user, uint256 amount);
    event DepositProcessed(uint256 indexed fundId, address indexed user, uint256 amount, uint256 sharesAmount);

    event WithdrawalRequested(uint256 fundId, address indexed user, uint256 amount);
    event Withdrawal(uint256 fundId, address indexed user, uint256 amount);
    event WithdrawalCancelled(uint256 fundId, address indexed user, uint256 amount);

    event FundsTransferredToTrader(uint256 fundId, address trader, uint256 amount);

    event FeesChanged(address newFees);
    /**
    * Public
    */

    function stake(uint256 fundId, address user, uint256 amount) external returns (uint256 stakedAmount);

    function requestWithdrawal(uint256 fundId, address user, uint256 amount) external;

    function cancelDeposit(uint256 fundId, address user) external returns (uint256);
    function cancelWithdrawal(uint256 fundId, address user) external returns (uint256);

    /**
    * Auth
    */

    function newFund(uint256 fundId,
        address manager,
        uint256 minStakingAmount,
        uint256 minWithdrawalAmount,
        IToken itoken,
        address trade,
        bool hwm
    ) external;

    function withdrawMultiple(uint256 fundId, address[] calldata users, uint256 supply, uint256 pf, uint256 tradeTvl) external;

    function drip(uint256 fundId, address trader, uint256 pf, uint256 tradeTvl) external;

    function gatherPF(uint256 fundId,  uint256 tradeTvl) external;

    /**
    * View
    */
    function userWaitingForWithdrawal(uint256 fundId) external view returns (address[] memory);
    function userWaitingForDeposit(uint256 fundId) external view returns(address[] memory);

    function tokenRate(uint256 fundId, uint256 tradeTvl) external view returns (uint256);
    function hwmValue(uint256 fundId) external view returns (uint256);
    function getInvestToken() external view returns(address);
    function pendingTvl(uint256 fundId, uint256 tradeTvl) external view returns (uint256, uint256, uint256);
    function calculatePf(uint256 fundId, uint256 tradeTvl) external view returns (uint256);
    function fundWithdrawals(uint256 fundId) external view returns (uint256);
    function getUserAccrual(uint256 fundId, address user) external view returns (uint256, uint256);
    function getUserData(uint256 fundId, address user) external view returns (uint256, uint256, uint256, uint256);
    function managers(uint256 fundId) external view returns(address);
}

