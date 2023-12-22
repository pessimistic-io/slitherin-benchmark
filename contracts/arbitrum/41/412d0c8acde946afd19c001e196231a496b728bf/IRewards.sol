
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./IRewardsStorage.sol";

/**
* @param stakingToken The LP Token to be staked
* @param rewardToken The reward token that is given by the Masterchef
* @param allocationPoints The allocation point for that particular pool (amount of rewards of the pool)
* @param lastRewardBlock The last block that distributes rewards.
* @param accRewardPerShare The accumulated rewards per share
*/
struct Pool {
    address stakingToken;
    address rewardToken;
    uint256 allocationPoints;
    uint256 lastRewardBlock;
    uint256 accRewardPerShare;
    bool isLending;
    address lendingToken;
}


/// @notice Info of each MCV2 user.
/// `amount` LP token amount the user has provided.
/// `rewardPaid` The amount of RUMI paid to the user.
/// `pendingRewards` The amount of RUMI pending to be paid after withdraw
    struct UserInfo {
        uint256 amount;
        uint256 rewardPaid;
        uint256 pendingRewards;
        uint256 rewardDebt;
    }

interface IRewards is IRewardsStorage {
    
    /**
     * @notice Event emitted on a user or vault depositing tokens
     * @param user User that deposits into the vault+masterchef
     * @param pid Pool Id of the deposit
     * @param amount Number of tokens staked     
     */
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);

    /**
     * @notice Event emitted on a user or vault withdrawing tokens
     * @param user User withdrawing
     * @param pid Pool Id of the deposit
     * @param amount Number of tokens staked to withdraw            
     */
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    
    /**
     * @notice Event emitted on an emergency withdraw scenario
     * @param user User withdrawing
     * @param pid Pool Id of the deposit
     * @param amount Number of tokens staked to withdraw            
     */
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    /**
     * @notice Event emitted on a user  harvesting of tokens
     * @param user User that deposits into the vault+masterchef
     * @param pid Pool Id of the deposit
     * @param amount Number of tokens harvested     
     */
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);    
    

    /**
     * @notice It sets caller whitelist, allowing vaults to call the Masterchef for autostaking
     * @param _callerToWhitelist address of caller to whitelist
     * @param _setOrUnset to set or unset whitelisted user
     */
    function setCallerWhitelist(address _callerToWhitelist, bool _setOrUnset) external;

    /**
     * @notice Change the speed of reward distributions
     * @param _rewardPerBlock the amount of rewards distributed per block
     */
    function changeRewardsPerBlock(uint256 _rewardPerBlock) external;    

    /**
     * @notice Sets the parameters of activation of caller whitelisting and enabling withdraws
     * @param _callerWhitelistActive Parameter to set or unset the caller whitelist
     * @param _withdrawEnabled It activates or deactivates withdrawals from users
     */
    function setParameters(bool _callerWhitelistActive, bool _withdrawEnabled) external;

    /**
     * @notice Returns the length of the pools
     * @return Number of pools
     */
    function poolLength() external view returns (uint256);

    /**
     * @notice Returns the pool id of a pool with address
     * @param _poolAddress address of the pool id to get
     * @param _isLending if the address to search is a lending pool
     * @param _lendingToken the lending token to search for
     * @return poolId Id of the pool
     * @return exists if the pool exists
     */
    function getPoolId(address _poolAddress, bool _isLending, address _lendingToken) external view returns (uint256 poolId, bool exists);
            
    /**
     * @notice It adds a Pool to the Masterchef array of pools
     * @param _stakingToken The Address Strategy or Vault token to be staked
     * @param _rewardToken The reward token to be distributed normally RUMI.
     * @param _allocationPoints The total tokens (allocation points) that the pool will be entitled to.
     * @param _isLending Is it a lending vault token
     * @param _lendingToken the lending token address
     */
    function addPool(address _stakingToken, address _rewardToken, uint256 _allocationPoints, bool _isLending, address _lendingToken) external;

    /**
     * @notice It sets a Poolwith new parameters
     * @param _pid The pool Id
     * @param _allocationPoints The reward token to be distributed normally RUMI.     
     */
    function setPool(uint256 _pid, uint256 _allocationPoints) external;    

    /**
     * @notice Sets the new Endblock to finish reward emissions
     * @param _endBlock The ending block     
     */
    function setEndblock(uint256 _endBlock) external;     
    
    /**
     * @notice Gets the pending rewards to be distributed to a user
     * @param _pid Pool id to consult
     * @param _user The address of the user that the function will check for pending rewards
     * @return rewards Returns the amount of rewards
     */
    function getPendingReward(uint256 _pid, address _user) external view returns (uint256 rewards);

    /**
     * @notice Gets the staked balance
     * @param _poolAddress Pool address to check
     * @param _user The address of the user that the function will check for pending rewards
     * @param _isLending is this a lending pool
     * @param _lendingToken the lending token to consult
     * @return stakedBalance Returns the amount of staked tokens
     */
    function balanceOf(address _poolAddress, address _user, bool _isLending, address _lendingToken) external view returns (uint256 stakedBalance);

    /**
     * @notice Gets the staked balance
     * @param _poolAddress Pool address to check
     * @param _user The address of the user that the function will check for pending rewards
     * @param _isLending is this a lending pool
     * @param _lendingToken the lending token to consult
     * @return harvestBalance Returns the amount of pending rewards to be harvested
     */
    function getPendingHarvestableRewards(address _poolAddress, address _user, bool _isLending, address _lendingToken) external view returns (int256 harvestBalance);
    
    /**
     * @notice Deposit into the masterchef, done either by pool or user
     * @param _pid Pool ID to deposit to
     * @param _amount amount to deposit
     * @param _depositor the depositor (user or vault)
     */
    function deposit(uint256 _pid, uint256 _amount, address _depositor) external;

    /**
     * @notice Deposit into the masterchef, done either by pool or user
     * @param _poolAddress Pool address to deposit to
     * @param _amount amount to deposit
     * @param _depositor the depositor (user or vault)
     * @param _isLending is the deposit for a lending token
     * @param _lendingToken if it is lending token what is the address
     */
    function deposit(address _poolAddress, uint256 _amount, address _depositor, bool _isLending, address _lendingToken) external;
    
    /**
     * @notice Withdraw from the masterchef, done either by the pool (unstaking)
     * @param _poolAddress Pool address to withdraw to
     * @param _amount amount to deposit
     * @param _depositor the depositor (user or vault)
     * @param _isLending is the deposit for a lending token
     * @param _lendingToken if it is lending token what is the address
     */
    function withdraw(address _poolAddress, uint256 _amount, address _depositor, bool _isLending, address _lendingToken) external;

    /**
     * @notice Harvest from the masterchef, done by user
     * @param _poolAddress Pool address to withdraw to          
     * @param _isLending is the deposit for a lending token
     * @param _lendingToken if it is lending token what is the address
     */
    function harvest(address _poolAddress, bool _isLending, address _lendingToken) external;


    /**
     * @notice Withdraw everything from the Maserchef
     * @param _pid Pool ID to deposit to       
     */
    function emergencyWithdraw(uint256 _pid) external;    

    /**
     * @notice Withdraw leftover tokens from Masterchef
     * @param _amount amount of tokens to withdraw
     * @param _rewardToken reward token address
     */
    function withdrawAllLeftoverRewards(uint256 _amount, address _rewardToken) external;    

    /**
     * @notice Update reward variables for all pools. Be careful of gas spending!
     * @param pids Pool IDs of all to be updated. Make sure to update all active pools.
     */
    function massUpdatePools(uint256[] calldata pids) external;
    
}
