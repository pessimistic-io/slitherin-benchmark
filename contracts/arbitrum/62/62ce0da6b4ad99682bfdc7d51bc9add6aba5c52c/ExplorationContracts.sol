//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./ExplorationState.sol";

abstract contract ExplorationContracts is Initializable, ExplorationState {
	
	function __ExplorationContracts_init() internal initializer {
		ExplorationState.__ExplorationState_init();
	}

	function setContracts(address _tldAddress, address _barnAddress)
		external
		onlyAdminOrOwner
	{
		tld = IERC721Upgradeable(_tldAddress);
		barn = IBarn(_barnAddress);
	}

	modifier contractsAreSet() {
		require(areContractsSet(), "Exploration: Contracts aren't set");
		_;
	}

	function areContractsSet() public view returns(bool) {
		return address(tld) != address(0)
			&& address(barn) != address(0);
	}
}
