// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./Pausable.sol";
import "./EnumerableSet.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IContractRegistry.sol";

/// @title Contract Registry
/// @author Buooy
/// @notice Contract registry
contract ContractRegistry is Initializable, OwnableUpgradeable, PausableUpgradeable, IContractRegistry {
  using EnumerableSet for EnumerableSet.AddressSet;
  EnumerableSet.AddressSet private strategyAddresses;
  
  //  ============================================================
  //  Initialisation
  //  ============================================================
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __Ownable_init();
    __Pausable_init();
  }

  // =======================================================================
  // Getters / Setters
  // =======================================================================
  /// @inheritdoc IContractRegistry
  function addNewStrategy(address strategyAddress) external onlyOwner {
    strategyAddresses.add(strategyAddress);
  }

  /// @inheritdoc IContractRegistry
  function getStrategies() public view returns (address[] memory strategies) {
    address[] memory _strategies = new  address[](strategyAddresses.length());
    for (uint index = 0; index < strategyAddresses.length(); index++) {
      _strategies[index] = strategyAddresses.at(index);
    }

    return _strategies;
  }
}
