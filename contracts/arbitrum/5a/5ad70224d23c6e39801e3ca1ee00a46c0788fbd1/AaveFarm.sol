// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { SafeERC20, IERC20 } from "./SafeERC20.sol";
import { IUniswapV2Pair } from "./IUniswapV2Pair.sol";
import { IFarmable, HarvestSwapParams } from "./IFarmable.sol";
import { ILending } from "./ILending.sol";

// import "hardhat/console.sol";

abstract contract AaveFarm is ILending, IFarmable {
	using SafeERC20 for IERC20;

	constructor(address router_, address token_) {}

	function lendFarmRouter() public pure override returns (address) {
		return address(0);
	}

	function _harvestLending(HarvestSwapParams[] calldata swapParams)
		internal
		virtual
		override
		returns (uint256[] memory harvested)
	{}
}

