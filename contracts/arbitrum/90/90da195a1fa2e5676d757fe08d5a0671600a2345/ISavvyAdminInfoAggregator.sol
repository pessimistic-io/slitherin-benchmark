// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

/// @title ISavvyAdminInfoAggregator
/// @author Savvy DeFi
///
/// @notice Simplifies the calls required to get protcol and user information.
/// @dev Used by the admin frontend.
interface ISavvyAdminInfoAggregator
{
  struct YieldStrategyMetrics {
    address savvyPositionManager;
    address yieldToken;
    uint256 yieldTokenBalance;
    address baseToken;
    uint256 baseTokenDecimals;
    uint256 expectedValueInBaseToken;
    uint256 maximumExpectedValueInBaseToken;
    bool enabled;
    address adapter;
  }

  /// @notice Set new InfoAggregator contract address.
  /// @dev Only owner can call this function.
  /// @param infoAggregator_ The address of infoAggregator.
  function setInfoAggregator(address infoAggregator_) external;

  /// @notice Get metrics for each yield strategy in Savvy.
  /// @dev iterates over all yield strategies from all the registered SPMs 
  /// in `infoAggregator` and returns metrics for each.
  /// @return metrics List of metrics for each yield strategy in Savvy.
  function getYieldStrategyMetrics() external view returns (YieldStrategyMetrics[] memory);
}

