// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

interface IRevenue {
    function distribute(bool _withReferee) external payable;
    function distribute(uint _amt, bool _withReferee) external;
    function lpDividend(address _account, uint _share, uint _total) external;
    function lpDividendUSDT(address _account, uint _share, uint _total) external;
    function stakeReward(address _account, uint _amt) external;
    function stakeRewardUSDT(address _account, uint _amt) external;
    function stake_revenue() view external returns (uint);
    function usdt_stake_revenue() view external returns (uint);
}

