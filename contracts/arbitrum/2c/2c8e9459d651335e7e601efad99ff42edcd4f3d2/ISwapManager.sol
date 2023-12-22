// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.17;

interface ISwapManager {
	function swap(
        address _assetIn,
        address _assetOut,
        uint256 _amountIn,
        uint256 _minAmountOut
	) external returns (uint256 amountOut);

        function updateWhitelistedCaller(
	address _caller,
	bool whitelist
	) external;
}
