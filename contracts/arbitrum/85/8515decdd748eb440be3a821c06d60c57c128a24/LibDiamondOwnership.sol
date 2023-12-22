// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./LibDiamondStorage.sol";

library LibDiamondOwnership {

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function setContractOwner(address _newOwner) internal {
       // DiamondStorage storage ds = diamondStorage();
	LibDiamondStorage.DiamondStorage storage ds = LibDiamondStorage.diamondStorage();
        address previousOwner = ds.contractOwner;
        ds.contractOwner = _newOwner;
        emit OwnershipTransferred(previousOwner, _newOwner);
    }

    function contractOwner() internal view returns (address contractOwner_) {
        contractOwner_ = LibDiamondStorage.diamondStorage().contractOwner;
    }

    function enforceIsContractOwner() internal view {
        require(msg.sender == LibDiamondStorage.diamondStorage().contractOwner, "LibDiamond: Must be contract owner");
    }
	
	modifier onlyContractOwner() {
		enforceIsContractOwner();
		_;
	}


}

