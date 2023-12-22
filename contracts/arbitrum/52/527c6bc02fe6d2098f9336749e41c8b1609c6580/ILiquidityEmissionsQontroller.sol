// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.9 <=0.8.19;

import "./IFixedRateMarket.sol";
import "./QTypes.sol";

interface ILiquidityEmissionsQontroller {
  /** EVENTS **/
  
  /// @notice Emitted when user claims emissions
  event ClaimEmissions(address indexed account, uint emission);
  
  /** ACCESS CONTROLLED FUNCTIONS **/
  
  /// @notice Distribute cumulated reward to the top-of-book
  /// Function will be invoked whenever quotes within a market is updated, which happens when:
  /// - New quote is created
  /// - Existing quote gets filled
  /// - Existing quote gets cancelled
  /// - Market expiry is reached
  /// @param market `FixedRateMarket` contract where quote update happens
  /// @param side Order book side for reward to be distributed. 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param currQuoteId Id of the newly created quote
  function updateRewards(IFixedRateMarket market, uint8 side, uint64 currQuoteId) external;
  
  /// @notice Function to set number of token to distribute per second for given market
  /// @param market `FixedRateMarket` contract
  /// @param rewardPerSec_ Number of token to distribute per second, scaled to decimal of the token
  function _setRewardPerSec(address market, uint rewardPerSec_) external;
  
  /// @notice Function to set all detail related for given market, can only be invoked once.
  /// Note that reward token should be approved on sender side before this function is invoked.
  /// @param market `FixedRateMarket` contract
  /// @param rewardTokenAddress Address of reward token to distribute
  /// @param rewardPerSec_ Number of token to distribute per second, scaled to decimal of the token
  /// @param allocation Maximum reward given market can distribute to user, scaled to decimal of the token
  function _setMarketInfo(address market, address rewardTokenAddress, uint rewardPerSec_, uint allocation) external;
  
  /// @notice Function to start reward distribution for given market, can only be invoked once.
  /// @param startSec start time in second for reward distribution, 0 for current time
  function _startDistribution(address market, uint startSec) external;
  
  /// @notice Withdraw the specified amount if possible.
  /// @param rewardTokenAddress Address of reward token to withdraw
  /// @param amount the amount to withdraw
  function _withdraw(address rewardTokenAddress, uint amount) external;
  
  /** USER INTERFACE **/
  
  /// @notice Distribute cumulated reward to the top-of-book for specified market and side
  /// Unless forcing reward emission in given market is needed (e.g. user is top-of-book but there 
  /// is no market activity), user can simply rely on market contract to manage reward distribution
  /// @param market `FixedRateMarket` contract where quote update happens
  /// @param side Order book side for reward to be distributed. 0 for borrow `Quote`, 1 for lend `Quote`
  function updateRewards(IFixedRateMarket market, uint8 side) external;
  
  /// @notice Mint unclaimed rewards to user and reset their claimable emissions
  function claimEmissions() external;
  
  /// @notice Mint unclaimed rewards to specified account and reset their claimable emissions
  /// @param account Address of the user
  function claimEmissions(address account) external;
  
  /// @notice Do top-of-book calculation for given market before transferring unclaimed reward to specified account and resetting
  /// @param account Address of the user
  /// @param market `FixedRateMarket` contract where quote update happens
  function claimEmissionsWithRewardUpdate(address account, IFixedRateMarket market) external;
  
  /** VIEW FUNCTIONS **/
    
  /// @notice Check if given account is top-of-book of specified side of the market
  /// Note that function assumes quotes in each market is ordered by best APR first, 
  /// followed by quote creation sequence in case of ties
  /// @param market `FixedRateMarket` contract for top-of-book check
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param account Address of the user
  /// @return bool true if account is currently top-of-book of specified side of the market
  function isTopOfBook(IFixedRateMarket market, uint8 side, address account) external view returns(bool);
  
  /// @notice Check if given account is top-of-book of specified side of the market,
  /// starting with given quote id
  /// Note that function assumes quotes in each market is ordered by best APR first, 
  /// followed by quote creation sequence in case of ties
  /// @param market `FixedRateMarket` contract for top-of-book check
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @param account Address of the user
  /// @param startQuoteId Quote id to start top-of-book check
  /// @return bool true if account is currently top-of-book of specified side of the market
  function isTopOfBook(IFixedRateMarket market, uint8 side, address account, uint64 startQuoteId) external view returns(bool);
  
  /// @notice Get top-of-book quote of specified side of the market
  /// @param market `FixedRateMarket` contract for top-of-book check
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @return QTypes.Quote top-of-book quote for specified side of the market
  function getQuoteEligibleForReward(IFixedRateMarket market, uint8 side) external view returns (QTypes.Quote memory);
  
  /// @notice Get top-of-book quote of specified side of the market,
  /// starting with given quote id
  /// @param market `FixedRateMarket` contract for top-of-book check
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @return QTypes.Quote top-of-book quote for specified side of the market
  function getQuoteEligibleForReward(IFixedRateMarket market, uint8 side, uint64 startQuoteId) external view returns (QTypes.Quote memory);
  
  /// @notice Get the address of the `QAdmin` contract
  /// @return address Address of `QAdmin` contract
  function qAdmin() external view returns(address);

  /// @notice Get the address of the reward token to distribute
  /// @param marketAddress `FixedRateMarket` contract address
  /// @return address Address of the reward token to distribute
  function rewardToken(address marketAddress) external view returns(address);
  
  /// @notice Get reward pending to claim for specified account
  /// @param account Account to query
  /// @param rewardTokenAddress Address of reward token to distribute
  /// @return uint reward pending to claim for specified account, scaled to decimal of the token
  function pendingReward(address account, address rewardTokenAddress) external view returns(uint);
  
  /// @notice Get amount per second to grant top-of-book quoter with given market
  /// @param marketAddress `FixedRateMarket` contract address
  /// @return Reward per second, scaled to decimal of the token
  function rewardPerSec(address marketAddress) external view returns(uint);
  
  /// @notice Get last reward distribution time for given market and side
  /// @param marketAddress `FixedRateMarket` contract address
  /// @param side 0 for borrow `Quote`, 1 for lend `Quote`
  /// @return Last reward distribution time, measured in second
  function lastDistributeTime(address marketAddress, uint8 side) external view returns(uint);
  
  /// @notice Get total allocated token balance for given market
  /// @param marketAddress `FixedRateMarket` contract address
  /// @return Total allocated token balance for given market, scaled to decimal of the token
  function totalAllocation(address marketAddress) external view returns(uint);
  
  /// @notice Get remaining allocated token balance for given market
  /// @param marketAddress `FixedRateMarket` contract address
  /// @return Remaining allocated token balance for given market, scaled to decimal of the token
  function remainingAllocation(address marketAddress) external view returns(uint);
}

