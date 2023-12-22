// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./Context.sol";
import "./LibDiamond.sol";
contract AdminUpdateWormholeFacet is Context {
	
	// --- all contract events listed here

	event UpdateWormhole(address previousWormhole, address newWormhole);
	// --- end of events
	

	/**
	* @notice AdminFacet update finality
    */
	function updateWormhole(
		address _wormhole
	) external {
		LibDiamond.enforceIsContractOwner();
		LibDiamond.DiamondStorage storage diamondStorage = LibDiamond.diamondStorage();
		emit UpdateWormhole(diamondStorage.wormhole, _wormhole);
		diamondStorage.wormhole = _wormhole;
	}
	
	function getWormhole() external view returns (address) {
		LibDiamond.DiamondStorage storage diamondStorage = LibDiamond.diamondStorage();
		return diamondStorage.wormhole;
	}
} // end of contract

