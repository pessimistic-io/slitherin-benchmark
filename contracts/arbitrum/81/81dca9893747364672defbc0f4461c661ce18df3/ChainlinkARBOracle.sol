// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./Pausable.sol";
import "./SafeCast.sol";
import "./AggregatorV3Interface.sol";

contract ChainlinkARBOracle is Ownable, Pausable {
  using SafeCast for int256;

  AggregatorV3Interface internal sequencerUptimeFeed;
  error SequencerDown();
  error GracePeriodNotOver();

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;
  uint256 public constant SEQUENCER_GRACE_PERIOD_TIME = 1 hours;

  /* ========== STRUCTS ========== */

  struct ChainlinkResponse {
    uint80 roundId;
    int256 answer;
    uint256 timestamp;
    bool success;
    uint8 decimals;
  }

  /* ========== MAPPINGS ========== */

  // Mapping of token to Chainlink USD price feed
  mapping(address => address) public feeds;
  // Mapping of token to maximum delay allowed (in seconds) of last price update
  mapping(address => uint256) public maxDelays;
  // Mapping of token to maximum % deviation allowed (in 1e18) of last price update
  mapping(address => uint256) public maxDeviations;

  /* ========== CONSTRUCTOR ========== */
  constructor(address _sequencerFeed) {
    sequencerUptimeFeed = AggregatorV3Interface(
      _sequencerFeed
    );
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  /**
    * Add Chainlink price feed for token
    * @param _token Token address
    * @param _feed Chainlink price feed address
    */
  function addTokenPriceFeed(address _token, address _feed) external onlyOwner {
    require(_token != address(0), "Invalid token address");
    require(_feed != address(0), "Invalid feed address");
    require(feeds[_token] == address(0), "Cannot reset a token price feed");

    feeds[_token] = _feed;
  }

  /**
    * Add Chainlink max delay for token
    * @param _token Token address
    * @param _maxDelay  Max delay allowed in seconds
    */
  function addTokenMaxDelay(address _token, uint256 _maxDelay) external onlyOwner {
    require(_token != address(0), "Invalid token address");
    require(feeds[_token] != address(0), "Invalid token feed");
    require(_maxDelay >= 0, "Max delay must be >= 0");

    maxDelays[_token] = _maxDelay;
  }

  /**
    * Add Chainlink max deviation for token
    * @param _token Token address
    * @param _maxDeviation  Max deviation allowed in seconds
    */
  function addTokenMaxDeviation(address _token, uint256 _maxDeviation) external onlyOwner {
    require(_token != address(0), "Invalid token address");
    require(feeds[_token] != address(0), "Invalid token feed");
    require(_maxDeviation >= 0, "Max deviation must be >= 0");

    maxDeviations[_token] = _maxDeviation;
  }

  /**
    * Emergency pause of this oracle
  */
  function emergencyPause() external onlyOwner whenNotPaused {
    _pause();
  }

  /**
    * Emergency resume of this oracle
  */
  function emergencyResume() external onlyOwner whenPaused {
    _unpause();
  }

  /* ========== VIEW FUNCTIONS ========== */

  /**
    * Get token price from Chainlink feed
    * @param _token Token address
    * @return price Asset price in int256
    * @return decimals Price decimals in uint8
    */
  function consult(address _token) public view whenNotPaused returns (int256, uint8) {
    address feed = feeds[_token];
    require(feed != address(0), "No price feed available for this token");

    ChainlinkResponse memory chainlinkResponse = _getChainlinkResponse(feed);
    ChainlinkResponse memory prevChainlinkResponse = _getPrevChainlinkResponse(feed, chainlinkResponse.roundId);

    require(!_chainlinkIsFrozen(chainlinkResponse, _token), "Chainlink price feed is frozen");

    require(!_chainlinkIsBroken(chainlinkResponse, prevChainlinkResponse, _token), "Chainlink price feed is broken");

    return (chainlinkResponse.answer, chainlinkResponse.decimals);
  }

  /**
    * Get token price from Chainlink feed returned in 1e18
    * @param _token Token address
    * @return price Asset price; expressed in 1e18
    */
  function consultIn18Decimals(address _token) external view whenNotPaused returns (uint256) {
    (int256 answer, uint8 decimals) = consult(_token);

    return answer.toUint256() * 1e18 / (10 ** decimals);
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
    * Check if Chainlink oracle is not working as expected
    * @param _currentResponse Current Chainlink response
    * @param _prevResponse Previous Chainlink response
    * @param _token Token address
    * @return Status of check in boolean
  */
  function _chainlinkIsBroken(
    ChainlinkResponse memory _currentResponse,
    ChainlinkResponse memory _prevResponse,
    address _token
  ) internal view returns (bool) {
    return _badChainlinkResponse(_currentResponse) ||
           _badChainlinkResponse(_prevResponse) ||
           _badPriceDeviation(_currentResponse, _prevResponse, _token);
  }

  /**
    * Checks to see if Chainlink oracle is returning a bad response
    * @param _response Chainlink response
    * @return Status of check in boolean
  */
  function _badChainlinkResponse(ChainlinkResponse memory _response) internal view returns (bool) {
    // Check for response call reverted
    if (!_response.success) {return true;}
    // Check for an invalid roundId that is 0
    if (_response.roundId == 0) {return true;}
    // Check for an invalid timeStamp that is 0, or in the future
    if (_response.timestamp == 0 || _response.timestamp > block.timestamp) {return true;}
    // Check for non-positive price
    if (_response.answer <= 0) {return true;}

    return false;
  }

  /**
    * Check to see if Chainlink oracle response is frozen/too stale
    * @param _response Chainlink response
    * @param _token Token address
    * @return Status of check in boolean
  */
  function _chainlinkIsFrozen(ChainlinkResponse memory _response, address _token) internal view returns (bool) {
    return (block.timestamp - _response.timestamp) > maxDelays[_token];
  }

  /**
    * Check to see if Chainlink oracle current response's price price deviation
    * is too large compared to previous response's price
    * @param _currentResponse Current Chainlink response
    * @param _prevResponse Previous Chainlink response
    * @param _token Token address
    * @return Status of check in boolean
  */
  function _badPriceDeviation(
    ChainlinkResponse memory _currentResponse,
    ChainlinkResponse memory _prevResponse,
    address _token
  ) internal view returns (bool) {
    // Check for a deviation that is too large
    uint256 deviation;

    if (_currentResponse.answer > _prevResponse.answer) {
      deviation = uint256(_currentResponse.answer - _prevResponse.answer) * SAFE_MULTIPLIER / uint256(_prevResponse.answer);
    } else {
      deviation = uint256(_prevResponse.answer - _currentResponse.answer) * SAFE_MULTIPLIER / uint256(_prevResponse.answer);
    }

    return deviation > maxDeviations[_token];
  }

  /**
    * Get latest Chainlink response
    * @param _feed Chainlink oracle feed address
    * @return ChainlinkResponse struct
  */
  function _getChainlinkResponse(address _feed) internal view returns (ChainlinkResponse memory) {
    ChainlinkResponse memory chainlinkResponse;

    chainlinkResponse.decimals = AggregatorV3Interface(_feed).decimals();

    (
      /*uint80 roundID*/,
      int256 answer,
      uint256 startedAt,
      /*uint256 updatedAt*/,
      /*uint80 answeredInRound*/
    ) = sequencerUptimeFeed.latestRoundData();

    // Answer == 0: Sequencer is up
    // Answer == 1: Sequencer is down
    bool isSequencerUp = answer == 0;
    if (!isSequencerUp) {
      revert SequencerDown();
    }

    // Make sure the grace period has passed after the
    // sequencer is back up.
    uint256 timeSinceUp = block.timestamp - startedAt;
    if (timeSinceUp <= SEQUENCER_GRACE_PERIOD_TIME) {
      revert GracePeriodNotOver();
    }

    (
      uint80 latestRoundId,
      int256 latestAnswer,
      /* uint256 startedAt */,
      uint256 latestTimestamp,
      /* uint80 answeredInRound */
    ) = AggregatorV3Interface(_feed).latestRoundData();

    chainlinkResponse.roundId = latestRoundId;
    chainlinkResponse.answer = latestAnswer;
    chainlinkResponse.timestamp = latestTimestamp;
    chainlinkResponse.success = true;

    return chainlinkResponse;
  }

  /**
    * Get previous round's Chainlink response from current round
    * @param _feed Chainlink oracle feed address
    * @param _currentRoundId Current roundId from current Chainlink response
    * @return ChainlinkResponse struct
  */
  function _getPrevChainlinkResponse(address _feed, uint80 _currentRoundId) internal view returns (ChainlinkResponse memory) {
    ChainlinkResponse memory prevChainlinkResponse;

    (
      uint80 roundId,
      int256 answer,
      /* uint256 startedAt */,
      uint256 timestamp,
      /* uint80 answeredInRound */
    ) = AggregatorV3Interface(_feed).getRoundData(_currentRoundId - 1);

    prevChainlinkResponse.roundId = roundId;
    prevChainlinkResponse.answer = answer;
    prevChainlinkResponse.timestamp = timestamp;
    prevChainlinkResponse.success = true;

    return prevChainlinkResponse;
  }
}

