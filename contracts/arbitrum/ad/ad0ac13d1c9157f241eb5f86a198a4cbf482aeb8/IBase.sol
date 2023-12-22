// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IERC20 } from "./SafeERC20.sol";
import { HarvestSwapParams } from "./Structs.sol";

// all interfaces need to inherit from base
abstract contract IBase {
	bool public isInitialized;

	modifier initializer() {
		require(isInitialized == false, "INITIALIZED");
		_;
	}

	function short() public view virtual returns (IERC20);

	function underlying() public view virtual returns (IERC20);
}

