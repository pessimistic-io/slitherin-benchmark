// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStakingSnapshot {
    
    struct Reward {
        uint gain;
        uint loss; 
    }

    // --- Events ---
    event DepositSnapshotUpdated(address indexed _depositor, uint _P, Reward _S, uint _G);
    event StakingContractAddressChanged(address _newStakingContractAddress);
    event StakingLoss(uint _stakingLoss, uint totalUSD, Reward RewardPerUnitStaked, uint GainLossPerUnitStaked);
    event StakingReward(uint amount, uint totalUSD, Reward RewardPerUnitStaked, uint GainLossPerUnitStaked);

    // --- Functions ---
    
    function setAddresses(address _StakingContractAddress) external;
    function addLoss(uint _amount) external;
    function addReward(uint _amount) external;
    function increaseTotalUSDDeposits(uint _amount) external;
    function decreaseTotalUSDDeposits(uint _amount) external;
    function updateDepositAndSnapshots(address _depositor, uint _newValue) external;
    function getCompoundedUSDDeposit(address _depositor) external view returns (uint);
    function getDepositorRewardGain(address _depositor) external view returns (uint amount);
    function totalUSDDeposits() external view returns (uint amount);
}

