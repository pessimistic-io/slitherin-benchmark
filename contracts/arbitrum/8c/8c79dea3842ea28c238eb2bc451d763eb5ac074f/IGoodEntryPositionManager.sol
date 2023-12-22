// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;


import "./IERC721Metadata.sol";
import "./IERC721Enumerable.sol";

interface IGoodEntryPositionManager is IERC721Metadata, IERC721Enumerable {  
  enum OptionType {FixedOption, StreamingOption}
  struct Position {
    bool isCall;
    /// @notice option type: 0: regular, 1: streaming
    OptionType optionType;
    uint strike;
    uint notionalAmount;
    uint collateralAmount;
    uint startDate;
    /// @dev if streaming option, this will be fundingRate, if fixed option: endDate
    uint data;
  }
  
  function initProxy(address _oracle, address _baseToken, address _quoteToken, address _vault, address _referrals) external;
  
  /*return (
      MIN_POSITION_VALUE_X8, 
      MIN_COLLATERAL_AMOUNT, 
      FIXED_EXERCISE_FEE, 
      STREAMING_OPTION_TTE, 
      MIN_FIXED_OPTIONS_TTE, 
      MAX_FIXED_OPTIONS_TTE, 
      MAX_UTILIZATION_RATE, 
      MAX_STRIKE_DISTANCE_X2
    );*/
  function getParameters() external view returns (uint, uint, uint, uint, uint, uint, uint8, uint8);
  function vault() external returns (address);
  function openStrikes(uint) external returns (uint);
  function getOpenStrikesLength() external returns (uint);
  function getPosition(uint tokenId) external view returns (Position memory);
  //function openFixedPosition(bool isCall, uint strike, uint notionalAmount, uint endDate) external returns (uint tokenId);
  //function openStreamingPosition(bool isCall, uint notionalAmount, uint collateralAmount) external returns (uint tokenId);
  //function closePosition(uint tokenId) external;
  function getFeesAccumulated(uint tokenId) external view returns (uint feesAccumulated);
  function getValueAtStrike(bool isCall, uint price, uint strike, uint amount) external pure returns (uint vaultDue, uint pnl);
  function getAssetsDue() external view returns (uint baseAmount, uint quoteAmount);
  function getOptionPrice(bool isCall, uint strike, uint size, uint timeToExpirySec) external view returns (uint optionPriceX8);
  function strikeToOpenInterestCalls(uint strike) external view returns (uint);
  function strikeToOpenInterestPuts(uint strike) external view returns (uint);
  function getUtilizationRateStatus() external view returns (uint utilizationRate, uint maxOI);
  function getUtilizationRate(bool isCall, uint addedAmount) external view returns (uint utilizationRate);
  //function increaseCollateral(uint tokenId, uint newCollateralAmount) external;
}
