// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


import {ERC20} from "./ERC20.sol";

/**
 * @dev Extension of {ERC20} that allows token holders to vest tokens before withdraw
 * Useful in combination with ERC20Wrapper for locking up tokens
 * Default vesting schedule is linear
 * A user can have multiple vesting schedules
 */
abstract contract ERC20Vesting is ERC20 {
  /// Event: Vesting
  event Vested(address indexed user, uint256 amount);
  /// Event: update vesting duration
  event UpdatedVestingDuration(uint vestingDuration);
  /// Event: Send tokens to user while penalty for early unlock is burnt
  event Withdraw(address indexed user, uint256 unlockedAmount, uint256 lockedAmount);

  /// @notice vesting duration in seconds
  uint64 private _vestingDuration; 

  /// @notice Token vesting structure
  struct VestingSchedule {
    uint192 vestedAmount;
    uint64 startTime;
  }
  
  /// @notice Vesting schedules
  VestingSchedule[] private _vestingSchedules;

  /// @notice User vesting schedules
  mapping(address => uint256[]) private _userVestingSchedules;

  /// @notice Total vesting tokens
  uint256 private _totalVestingBalance;

  /// @notice Individual total vesting balance
  mapping(address => uint256) private _userVestingBalances;
  
  
  
  /// @dev Sets the the value for {vestingDuration}
  constructor(uint64 vestingDuration_){
    require(vestingDuration_ > 0, "ERC20Vesting: Zero vesting");
    _vestingDuration = vestingDuration_;
  }
  
  //////// GETTERS
  
  /// @notice Returns the vesting duration
  function vestingDuration() public view returns (uint256){
    return _vestingDuration;
  }
  
  /// @notice Returns total amount currently vesting
  function totalVestingBalance() public view returns (uint256) {
    return _totalVestingBalance;
  }
  
  /// @notice Returns the currently vesting balance for user
  function vestingBalanceOf(address user) public view returns (uint256) {
    return _userVestingBalances[user];
  }
  
  /// @notice Get number of vesting structs for a user
  function getVestingLength(address user) public view returns (uint256) {
    return _userVestingSchedules[user].length;
  }
  
  /// @notice Returns data for a vesting schedule
  /// @param vestedAmount Intial vested amount
  /// @param startTime Vesting start date
  /// @param unlockedAmount Amount already vested
  /// @param lockedAmount Amount remaining to vest
  /// @dev lockedAmount and unlockedAmount are not indicative of whether
  function getVestingSchedule(uint vestingId) 
    public view virtual 
    returns (uint256 vestedAmount, uint64 startTime, uint256 unlockedAmount, uint256 lockedAmount)
  {
    require(vestingId < _vestingSchedules.length, "ERC20Vesting: Invalid Schedule");
    VestingSchedule memory vs = _vestingSchedules[vestingId];
    vestedAmount  = uint256(vs.vestedAmount);
    startTime = vs.startTime;
    (unlockedAmount, lockedAmount) = vestingStatus(vestedAmount, startTime);
  }
  
  
  /// @notice Returns vesting Id 
  function getVestingScheduleId(address user, uint256 userVestingId) public view returns (uint256){
    require(userVestingId < getVestingLength(user), "ERC20Vesting: Invalid userVestingId");
    return _userVestingSchedules[user][userVestingId];
  }
  
  
  /// @notice Returns data for a user's vesting schedule
  function getUserVestingSchedule(address user, uint userVestingId)
    public view virtual 
    returns (uint256 vestedAmount, uint64 startTime, uint256 unlockedAmount, uint256 lockedAmount)
  {
    return getVestingSchedule(getVestingScheduleId(user, userVestingId));
  }
  
  
  /// @notice Update vesting duration
  /// @param vestingDuration_ New vesting duration
  function _updateVestingDuration(uint64 vestingDuration_) internal virtual {
    require(vestingDuration_ > 0, "ERC20Vesting: Invalid vesting duration");
    _vestingDuration = vestingDuration_;
    emit UpdatedVestingDuration(_vestingDuration);
  }  
  
  
  //////// VESTING LOGIC
  
  /// @notice Vest locked token
  /// @param vestingAmount Amount of tokens to vest
  function vest(uint vestingAmount) public virtual returns (uint userVestingId){
    address sender = _msgSender();
    _vest(sender, vestingAmount, uint64(block.timestamp));
    userVestingId = _userVestingSchedules[sender].length - 1;
  }
  
  
  /// @notice Vesting starts the unlock countdown for a user's subset of tokens
  function _vest(address user, uint256 vestingAmount, uint64 startTime) internal returns (uint vestingId) {
    require(balanceOf(user) >= vestingAmount + vestingBalanceOf(user), "ERC20Vesting: Insufficient Balance");
    require(vestingAmount > 0 || vestingAmount < type(uint224).max, "ERC20Vesting: Invalid Amount");
    require(startTime + _vestingDuration > block.timestamp, "ERC20Vesting: Invalid Time");
    _vestingSchedules.push(VestingSchedule(uint192(vestingAmount), startTime));
    vestingId = _vestingSchedules.length - 1;
    _userVestingSchedules[user].push(_vestingSchedules.length-1);
    _totalVestingBalance += vestingAmount;
    _userVestingBalances[user] += vestingAmount;
    emit Vested(user, vestingAmount);
  }

  
  /// @notice User can withdraw tokens once vesting is over
  /// @param user Owner of the vesting structure
  /// @param userVestingId Id of the vesting structure in the user list
  /// @return unlockedAmount Amount of tokens unlocked
  /// @return lockedAmount Amount of tokens remaining locked
  /// @dev Doesnt actually send anything, only does accounting and return values to be sent/burnt - doesn't check ownership
  function _withdraw(address user, uint256 userVestingId) internal returns (uint256 unlockedAmount, uint256 lockedAmount){
    uint userVestingLength = getVestingLength(user);
    uint256 vestedAmount;
    uint64 startTime;
    (vestedAmount, startTime, unlockedAmount, lockedAmount) = getUserVestingSchedule(user, userVestingId);

    // remove from user list
    if(userVestingId < userVestingLength - 1){
      _userVestingSchedules[user][userVestingId] = _userVestingSchedules[user][userVestingLength - 1];
    }
    _userVestingSchedules[user].pop();
    
    _totalVestingBalance -= vestedAmount;
    _userVestingBalances[user] -= vestedAmount;
    emit Withdraw(user, unlockedAmount, lockedAmount);
  }

  
  
  /// @notice Calculates the amount that can be received
  /// @param vestedAmount Amount of tokens vested
  /// @param startTime End of vesting timestamp
  /// @return unlockedAmount Amount of tokens unlocked
  /// @return lockedAmount Amount of tokens remaining locked
  function vestingStatus(uint256 vestedAmount, uint64 startTime) public view returns (uint256 unlockedAmount, uint256 lockedAmount) {
    if (block.timestamp >= startTime + _vestingDuration){
      unlockedAmount = vestedAmount;
    }
    else if (block.timestamp <= startTime){
      lockedAmount = vestedAmount;
    }
    else {
      (unlockedAmount, lockedAmount) = _vestingStatus(vestedAmount, startTime);
    }
  }
  
  
  /// @notice Calculate the actual unlocked/locked amounts for non trivial results, default is linear unlock
  function _vestingStatus(uint256 vestedAmount, uint64 startTime) internal view virtual returns (uint256 unlockedAmount, uint256 lockedAmount) {
    unlockedAmount = (vestedAmount * (block.timestamp - startTime)) / _vestingDuration;
    lockedAmount = vestedAmount - unlockedAmount;
  }
 
  //////// OVERRIDES
  
  // Transfer of vested tokens is forbidden by default
  function transfer(address to, uint256 value) public virtual override (ERC20) returns (bool) {
    revert("ERC20Vesting: Transfer Forbidden");
  }
  
  // Transfer of vested tokens is forbidden by default
  function transferFrom(address from, address to, uint256 value) public virtual override (ERC20) returns (bool) {
    revert("ERC20Vesting: Transfer Forbidden");
  }
  
}
