// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {LibDiamond} from "./LibDiamond.sol";
import {IERC173} from "./IERC173.sol";

contract OwnershipFacet is IERC173 {
    /**
     * @notice Transfer ownership.
     */
    function transferOwnership(address _newOwner) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.setContractOwner(_newOwner);
    }

    /**
     * @notice Get current owner.
     */
    function owner() external view override returns (address owner_) {
        owner_ = LibDiamond.contractOwner();
    }
}

