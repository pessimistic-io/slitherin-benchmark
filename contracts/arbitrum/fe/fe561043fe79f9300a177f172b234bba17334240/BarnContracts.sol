//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";

import "./BarnState.sol";

abstract contract BarnContracts is Initializable, BarnState {
	
	function __BarnContracts_init() internal initializer {
		BarnState.__BarnState_init();
	}

	function setContracts(address _barnMetadata, address _randomizerAddress) external onlyAdminOrOwner {
		barnMetadata = IBarnMetadata(_barnMetadata);
		randomizer = IRandomizer(_randomizerAddress);
	}

	modifier contractsAreSet() {
		require(areContractsSet(), "Barn: Contracts aren't set");
		_;
	}

	function areContractsSet() public view returns (bool) {
		return address(barnMetadata) != address(0)
		&& address(randomizer) != address(0);
	}
}
