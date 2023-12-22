// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.20;

import "./Ownable2StepUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

contract BalancerPoolHelper is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address initialOwner) public initializer {
    __Ownable2Step_init();
    __Ownable_init(initialOwner);
    __UUPSUpgradeable_init();
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

