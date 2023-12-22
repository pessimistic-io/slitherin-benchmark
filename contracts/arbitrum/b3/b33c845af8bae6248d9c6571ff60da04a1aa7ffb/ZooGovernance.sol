pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT

import "./IZooFunctions.sol";
import "./Ownable.sol";

/// @title Contract ZooGovernance.
/// @notice Contract for Zoo Dao vote proposals.
contract ZooGovernance is Ownable {

	address public zooFunctions;                    // Address of contract with Zoo functions.

	/// @notice Contract constructor.
	/// @param baseZooFunctions - address of baseZooFunctions contract.
	/// @param aragon - address of aragon zoo dao agent.
	constructor(address baseZooFunctions, address aragon) {

		zooFunctions = baseZooFunctions;

		transferOwnership(aragon);                  // Sets owner to aragon.
	}

	/// @notice Function for vote for changing Zoo fuctions.
	/// @param newZooFunctions - address of new zoo functions contract.
	function changeZooFunctionsContract(address newZooFunctions) external onlyOwner
	{
		zooFunctions = newZooFunctions;
	}

}
