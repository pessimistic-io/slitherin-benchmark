// SPDX-License-Identifier: BSL 1.1

pragma solidity ^0.8.17;

import "./IRewardsStorage.sol";
import "./IRewards.sol";

contract RewardsStorage is IRewardsStorage {

    /// @notice Reward rate per block
    uint256 public rewardPerBlock;    

    /// @notice The total amount of rewards available for all of the pools.
    // uint256 public totalAllocationPoints;   
    mapping(address=>uint256) public totalAllocationPoints;

    /// @notice The start block where the MasterChef starts distributing
    uint256 public startBlock;         

    /// @notice The end block where the MasterChef finishes distributing
    uint256 public endBlock;    

    /// @notice The available pools where the MasterChef is distributing
    Pool[] public pools;   
        
    /// @notice Info of each user that stakes LP tokens.
     mapping(uint256 => mapping (address => UserInfo)) public userInfo;

    /// @notice The accumulated amount of rewards of each user 
    mapping(uint256 => mapping(address => uint256)) public userAccumulatedReward;

    /// @notice Mapping to whitelist a caller AKA Pools that will virtually stake
    mapping(address=>bool) public callerWhitelist;
    
    /// @notice Is Caller whitelist activated
    bool public callerWhitelistActive;

    /// @notice Is Withdraw enabled
    bool public withdrawEnabled;
}
