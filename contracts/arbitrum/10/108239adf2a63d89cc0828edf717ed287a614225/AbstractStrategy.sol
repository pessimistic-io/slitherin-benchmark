// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./Pausable.sol";
import "./PausableUpgradeable.sol";
import "./EnumerableMap.sol";
import "./EnumerableSet.sol";
import "./console.sol";

import "./IPool.sol";
import "./AccessControls.sol";

abstract contract AbstractStrategy is Initializable, AccessControls, PausableUpgradeable {
  string public strategyName;
  string public strategyCategory;
  bool public isInitialised;

  // ================================================================================================
  // Events
  // ================================================================================================
  /// @notice This event is emitted when a strategy is initialised
  /// @param strategyAddress strategy address
  /// @param strategyName strategy name
  /// @param strategyCategory strategy category
  event StrategyInitialised (
    address strategyAddress,
    string strategyName,
    string strategyCategory
  );

  /// @notice This event is emitted when a strategy pool is deployed
  /// @param poolAddress pool address
  /// @param poolType pool type
  /// @param poolProtocol pool protocol
  /// @param poolTokens tokens that this pool manages
  event PoolDeployed (
    address poolAddress,
    string poolType,
    string poolProtocol,
    address[] poolTokens
  );

  // ================================================================================================
  // Security Functions
  // ================================================================================================
  /// @notice Pauses the strategy
  function pause() virtual external onlyOwner {
    _pause();
  }

  /// @notice Unpauses the strategy
  function unpause() virtual external onlyOwner {
    _unpause();
  }

  /// @notice allocates the current usdc in the vault into the underlying pools based on the allocation
  function allocate() virtual external;

  /// @notice pull from yielding pool and withdraw from lending pool
  function exitPositions() virtual external;

  // ================================================================================================
  // Getters/Setters
  // ================================================================================================
  /// @notice gets the strategy information
  /// @return name strategy name
  /// @return strategyCategory strategy category
  /// @return isStrategyInitialised is strategy initialised
  /// @return isStrategyPaused is strategy paused
  /// @return lendingPoolTokenAddresses address of the lending pool tokens
  /// @return lendingPoolTokenValues values of the lending pool tokens
  /// @return yieldingPoolTokenAddresses address of the yield pool tokens
  /// @return yieldingPoolTokenValues values of the yield pool tokens
  function getStrategyInfo() virtual external view returns (
    string memory name,
    string memory strategyCategory,
    bool isStrategyInitialised,
    bool isStrategyPaused,
    address[] memory lendingPoolTokenAddresses,
    uint256[] memory lendingPoolTokenValues,
    address[] memory yieldingPoolTokenAddresses,
    uint256[] memory yieldingPoolTokenValues
  );

  /// @notice gets the strategy information
  /// @return name strategy name
  /// @return category strategy type
  /// @return isStrategyInitialised is strategy initialised
  /// @return isStrategyPaused is strategy paused
  function _getStrategyInfo() virtual internal view returns (
    //  Basic Strategy Metadata
    string memory name,
    string memory category,
    bool isStrategyInitialised,
    bool isStrategyPaused
  ) {
    return (
      strategyName,
      strategyCategory,
      isInitialised,
      paused()
    );
  }

  /// @notice sets the withdraw address
  function setWithdrawAddress(address _withdrawAddress) virtual external;

  /// @notice gets the withdraw address
  function getWithdrawAddress() virtual external view returns (address);
}
