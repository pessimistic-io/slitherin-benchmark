// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface IRewardsStorage {
   
    function rewardPerBlock() external view returns (uint256);
    function totalAllocationPoints(address rewardAddress) external view returns (uint256);
    function startBlock() external view returns (uint256);
    function endBlock() external view returns (uint256);
    function pools(uint position) external view returns (address, address, uint256, uint256, uint256, bool, address);
    function userInfo(uint poolId, address userAddress) external view returns (uint256,uint256, uint256, uint256);    
    function userAccumulatedReward(uint poolId, address userAddress) external view returns (uint256);
        
}

