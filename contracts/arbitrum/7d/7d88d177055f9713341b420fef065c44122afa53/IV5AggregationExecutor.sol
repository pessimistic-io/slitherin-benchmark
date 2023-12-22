pragma solidity >=0.8.0;

/// @title Interface for making arbitrary calls during swap
interface IV5AggregationExecutor {
  /// @notice propagates information about original msg.sender and executes arbitrary data
  function execute(address msgSender) external payable; // 0x4b64e492
}

