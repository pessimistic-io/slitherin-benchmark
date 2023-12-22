// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IUniswapV3Pool {
	function slot0()
		external
		view
		returns (
			uint160 sqrtPriceX96,
			int24 tick,
			uint16 observationIndex,
			uint16 observationCardinality,
			uint16 observationCardinalityNext,
			uint8 feeProtocol,
			bool unlocked
		);

	function observe(uint32[] calldata secondsAgos)
		external
		view
		returns (
			int56[] memory tickCumulatives,
			uint160[] memory secondsPerLiquidityCumulativeX128s
		);

	function observations(uint256 index)
		external
		view
		returns (
			uint32 blockTimestamp,
			int56 tickCumulative,
			uint160 secondsPerLiquidityCumulativeX128,
			bool initialized
		);

	function liquidity() external view returns (uint128);
}

