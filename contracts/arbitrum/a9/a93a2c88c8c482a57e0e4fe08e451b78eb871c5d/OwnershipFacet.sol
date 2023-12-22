// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { LibDiamond } from "./LibDiamond.sol";

contract OwnershipFacet {
    function transferDiamondOwnership(address _newOwner) external {
        LibDiamond.enforceIsDiamondOwner();
        LibDiamond.setDiamondOwner(_newOwner);
    }

    function diamondOwner() external view returns (address diamondOwner_) {
        diamondOwner_ = LibDiamond.diamondOwner();
    }
}
