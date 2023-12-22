// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import { IStarchef } from "./IStarchef.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { HarvestSwapParams } from "./Structs.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20, IERC20 } from "./SafeERC20.sol";

// import "hardhat/console.sol";

struct FarmConfig {
	address farm;
	uint16 farmId;
	address router;
	address farmToken;
}

abstract contract StarChefFarm {
	using SafeERC20 for IERC20;

	IStarchef public farm;
	uint16 public farmId;
	ISwapRouter public farmRouter;
	IERC20 public farmToken;

	event HarvestedToken(address token, uint256 amount, uint256 amountUnderlying);

	constructor(FarmConfig memory farmConfig) {
		farm = IStarchef(farmConfig.farm);
		farmId = farmConfig.farmId;
		farmRouter = ISwapRouter(farmConfig.router);
		farmToken = IERC20(farmConfig.farmToken);
		farmToken.safeApprove(address(farmRouter), type(uint256).max);
	}

	function _withdrawFromFarm(uint256 amount) internal {
		farm.withdraw(farmId, amount);
	}

	function _depositIntoFarm(uint256 amount) internal {
		farm.deposit(farmId, amount);
	}

	function _getFarmLp() internal view returns (uint256 lp) {
		(lp, ) = farm.userInfo(farmId, address(this));
	}

	function _harvestFarm(HarvestSwapParams calldata swapParams)
		internal
		returns (uint256 harvested, uint256 amountOut)
	{
		farm.deposit(farmId, 0);
		harvested = farmToken.balanceOf(address(this));
		if (harvested == 0) return (0, 0);

		if (bytes20(swapParams.pathData) != bytes20(address(farmToken))) {
			revert InvalidPathData();
		}

		ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
			path: swapParams.pathData,
			recipient: address(this),
			deadline: block.timestamp,
			amountIn: harvested,
			amountOutMinimum: swapParams.min
		});
		amountOut = farmRouter.exactInput(params);
		emit HarvestedToken(address(farmToken), harvested, amountOut);
	}

	error InvalidPathData();
}

