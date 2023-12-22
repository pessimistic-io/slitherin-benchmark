// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./Context.sol";
import "./LibDiamond.sol";
contract AdminFacet is Context {
	
	// --- all contract events listed here

	event UpdateFinality(uint8 previousFinality, uint8 newFinality);
	// --- end of events
	
	
	/**
    * @notice AdminFacet update finality
    */
	function updateFinality(
		uint8 _finality
	) external {
		LibDiamond.enforceIsContractOwner();
		LibDiamond.DiamondStorage storage diamondStorage = LibDiamond.diamondStorage();
		emit UpdateFinality(diamondStorage.finality, _finality);
		diamondStorage.finality = _finality;
	}
	
	function getFinality() external view returns (uint8) {
		LibDiamond.DiamondStorage storage diamondStorage = LibDiamond.diamondStorage();
		return diamondStorage.finality;
	}
} // end of contract

