// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./Pausable.sol";
import "./PausableUpgradeable.sol";
import "./ERC165.sol";
import "./EnumerableSet.sol";
import "./console.sol";

import "./IPool.sol";
import "./AccessControls.sol";

abstract contract AbstractPool is IPool, AccessControls, PausableUpgradeable {
  receive() external payable {}

  // ==============================================================================================
  /// Contract Management Functions
  // ==============================================================================================
  /// @notice Pauses the contract
  /// @dev when paused, the contract should only allow read-only access to contract data
  /// @dev when paused, the contract should only be allowed to repay and withdraw from the lending
  /// @custom:access should only be callable by the deployer (hardware wallet)
  function pause() external onlyOwner {
      //  pauses the contract
      _pause();
  }

  /// @notice Unpauses the contract
  /// @dev when paused, the contract should only allow read-only access to contract data
  /// @dev when paused, the contract should only be allowed to repay and withdraw from the lending
  /// @custom:access should only be callable by the deployer (hardware wallet)
  function unpause() external onlyOwner {
      //  unpauses the contract
      _unpause();
  }

  function renounceOwnership() public view  onlyOwner override {
      revert("renounceOwnership is disabled");
  }
}
