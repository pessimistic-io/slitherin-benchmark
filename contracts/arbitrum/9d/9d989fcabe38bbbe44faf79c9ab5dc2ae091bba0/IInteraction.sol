// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IToken.sol";

interface IInteraction {

    struct FundInfo {
        address trade;
        uint256 period;
        uint256 nextPeriod;
        uint256 live;
        IToken itoken;
        bool hwm;
    }

    event NewFund(uint256 indexed fundId, address manager, address itoken);
    event NextPeriod(uint256 indexed fundId, uint256 nextPeriod);
    event Stake(uint256 indexed fundId, address user, uint256 depositAmount, uint256 tokenAmount, uint256 commissionPaid);
    event UnStake(uint256 indexed fundId, address user, uint256 amount, uint256 positionLeft);

    event FundStateChanged(uint256 indexed fundId, uint256 state);

    function newFund(uint256 fundId,
        bool hwm,
        uint256 investPeriod,
        uint256 minStakingAmount,
        uint256 minWithdrawalAmount,
        address manager,
        IToken itoken,
        address tradeContract
    ) external;

    function drip(uint256 fundId, uint256 tradeTvl) external;
    function withdrawMultiple(uint256 fundId, address[] calldata users, uint256 tradeTvl) external;
    function dripAndWithdraw(uint256 fundId, uint256 tradeTvl, address[] calldata users) external;

    function stake(uint256 fundId, uint256 amount) external returns (uint256);
    function unstake(uint256 fundId, uint256 amount) external;

    function show(uint256 fundId) external;
    function hide(uint256 fundId) external;
    // VIEWS

    function fundExist(uint256 fundId) external view returns(bool);

    function tokenForFund(uint256 fundId) external view returns (address);

    function tvl(uint256 fundId, uint256 tradeTvl) external view returns (int256);
    function stakers(uint256 fundId) external view returns (uint256);
    function fundInfo(uint256 fundId) external view returns (address, uint256, uint256);
    function tokenRate(uint256 fundId, uint256 tradeTvl) external view returns (uint256);
    function tokenSupply(uint256 fundId) external view returns (uint256);
    function quoteTokens(uint256 fundId, uint256 tradeTvl, uint256 usdt) external view returns (uint256);
    function userTokensAmount(uint256 fundId, address user) external view returns (uint256);
    function userTVL(uint256 fundId, uint256 tradeTvl, address user) external view returns (uint256);
    function pendingTvl(uint256 fundId, uint256 tradeTvl) external view returns (int256);
    function totalFees(uint256 fundId) external view returns (uint256);
    function pendingDepositAndWithdrawals(uint256 fundId, address user) external view returns (uint256, uint256);

    function cancelWithdraw(uint256 fundId) external;
    function cancelDeposit(uint256 fundId) external;

    function deposits(uint256 fundId) external view returns (uint256);
    function withdrawals(uint256 fundId) external view returns (uint256);
}

