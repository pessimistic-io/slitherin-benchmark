//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./SquareState.sol";

abstract contract SquareContracts is Initializable, SquareState {
    function __SquareContracts_init() internal initializer {
		SquareState.__SquareState_init();
	}

	function setContracts(address _squareMetadata) 
        external 
        onlyAdminOrOwner 
    {
		squareMetadata = ISquareMetadata(_squareMetadata);
	}

	modifier contractsAreSet() {
		require(areContractsSet(), "Square: Contracts aren't set");
		_;
	}

	function areContractsSet() public view returns (bool) {
		return address(squareMetadata) != address(0);
	}
}
