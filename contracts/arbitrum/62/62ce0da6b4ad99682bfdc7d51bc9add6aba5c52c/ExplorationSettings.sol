//SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Initializable.sol";
import "./ExplorationContracts.sol";

abstract contract ExplorationSettings is Initializable, ExplorationContracts {

	function __ExplorationSettings_init() internal initializer {
		ExplorationContracts.__ExplorationContracts_init();
	}
}
