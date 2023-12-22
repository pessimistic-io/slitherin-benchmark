// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC173 } from "./IERC173.sol";
import { LibOwnership } from "./LibOwnership.sol";
import { IDiamondInit } from "./IDiamondInit.sol";

error NotOwner();

contract OwnershipFacet is IERC173 {
  function transferOwnership(address _newOwner) external override {
    LibOwnership.enforceIsContractOwner();
    LibOwnership.setContractOwner(_newOwner);
  }

  function owner() external view override returns (address owner_) {
    owner_ = LibOwnership.contractOwner();
  }
}

contract OwnershipDiamondInit is IDiamondInit {
  function init() external {
    LibOwnership.setContractOwner(msg.sender);
  }
}

