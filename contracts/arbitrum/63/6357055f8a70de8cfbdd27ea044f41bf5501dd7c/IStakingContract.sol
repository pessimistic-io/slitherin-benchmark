// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IStakingContract {
    function getTotalUsdStake() external view returns (uint256);
    function notifyStakingLossAmount(uint amount) external;
    function deposit(uint usdAmount, uint blxAmount) external;
    function withdraw(uint usdAmount, uint blxAmount) external;
    function lock(uint duration) external;
    function lockWithBurn(uint duration) external;
    function claimReward(uint amount) external;
    function batchDistributeGainLoss(uint count) external returns (uint rewards);
    function distributeGainLoss(address account, bool claim) external;
}

