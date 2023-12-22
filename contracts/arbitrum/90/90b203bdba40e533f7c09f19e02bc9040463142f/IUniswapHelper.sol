//SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.6;

import "./IUniswapV3Pool.sol";

interface IUniswapHelper {
	function feesOf(uint256 _tokenId) view external returns (uint256 token0Fees, uint256 token1Fees, IUniswapV3Pool pool);
	
	// Note: Both returned TWAP and spot price values are pool token prices with 12 decimals (defined in PRECISION_DECIMALS)
	function getTWAPPrice(IUniswapV3Pool pool, uint32 interval, bool isToken0ETH) external view returns (uint256 price);
	function getSpotPrice(IUniswapV3Pool pool, bool isToken0ETH) external view returns (uint256 price);

	function PRECISION_DECIMALS() external view returns (uint256);
}

