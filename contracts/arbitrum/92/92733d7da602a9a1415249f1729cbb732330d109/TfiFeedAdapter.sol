// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./TfiFeedRegistry.sol";
import "./AggregatorV2V3Interface.sol";
import "./Initializable.sol";

contract TfiFeedAdapter is Initializable, AggregatorV2V3Interface {
  TfiFeedRegistry public registry;
  bytes32 public registryKey;
  function initialize(
    TfiFeedRegistry registry_,
    bytes32 registryKey_
  ) public initializer {
    registry = registry_;
    registryKey = registryKey_;
  }

  /**
   * @notice details for the given aggregator round
   * @param roundId target aggregator round (NOT OCR round). Must fit in uint32
   * @return roundId roundId
   * @return answer price of the pair at this round
   * @return startedAt timestamp of when observations were made offchain
   * @return updatedAt timestamp of block in which report from given roundId was transmitted
   * @return answeredInRound roundId
   */
  function getRoundData(uint80 roundId_)
    external
    view
    virtual
    override
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )
  {
    return registry.getRoundData(registryKey, roundId_, msg.sender);
  }

  /**
   * @notice aggregator details for the most recently transmitted report
   * @return roundId aggregator round of latest report (NOT OCR round)
   * @return answer price of the pair at this round
   * @return startedAt timestamp of when observations were made offchain
   * @return updatedAt timestamp of block containing latest report
   * @return answeredInRound aggregator round of latest report
   */
  function latestRoundData()
    external
    view
    virtual
    override
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    )
  {
    return registry.latestRoundData(registryKey, msg.sender);
  }

  function decimals() external pure returns (uint8) {
    return 18;
  }

  function description() external pure returns (string memory) {
    return "TfiFeedAdapter";
  }

  function version() external pure returns (uint256) {
    return 202304210;
  }

  /** Intentionally not implemented
      https://docs.chain.link/data-feeds/api-reference/
   */
  function getAnswer(uint256) external pure returns (int256) {
    revert("not implemented");
  }

  function getTimestamp(uint256) external pure returns (uint256) {
    revert("not implemented");
  }

  function latestAnswer() external pure returns (int256) {
    revert("not implemented");
  }

  function latestRound() external pure returns (uint256) {
    revert("not implemented");
  }

  function latestTimestamp() external pure returns (uint256) {
    revert("not implemented");
  }
}

