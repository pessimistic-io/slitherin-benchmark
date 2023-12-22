//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./IUniswapV3Pool.sol";

interface ITicketFundsProvider {
	event GetConvertedFunds(address indexed owner, uint256 indexed tokenId, uint256 ethAmount, uint256 timeMultipliedETHAmount,
		uint256 timeMultiplier, uint256 initialToken0Fees, uint256 initialToken1Fees, 
		uint256 collectedToken0Fees, uint256 collectedToken1Fees, uint256 token0ETHAmount, uint256 token1ETHAmount);
	event GetFunds(address indexed owner, uint256 indexed tokenId, uint256 collectedToken0Fees, uint256 collectedToken1Fees);

	// Note: price values are pool token prices with 12 decimals (defined in PRECISION_DECIMALS of the UniswapHelper contract)
	function getFunds(uint256 tokenId, address owner, uint256 ticketId, uint256 token0ETHPrice, uint256 token1ETHPrice) external returns (uint256 ethAmount, uint256 timeMultipliedETHAmount);
	function getFundsWithoutPrices(uint256 tokenId, uint256 ticketId, uint256 slippage) external returns (uint256 ethAmount, uint256 timeMultipliedETHAmount);

	function stakeWithTicket(uint256 tokenId, address owner, uint256 ticketId) external;
	function updateTicketInfo(uint256 tokenId, address owner, uint256 ticketId) external;
	function unstakeForOwner(uint256 tokenId, address owner, uint256 ticketId) external;

	function stakedPositions(uint256 tokenId) view external returns (address owner, uint256 timestamp, uint256 token0SFees, uint256 token1Fees, uint256 gameId, uint256 ticketId);
	function getTimeMultipliedFees(uint256 tokenId) external view returns (uint256 totalTimeMultipliedETHFees, uint256 timeMultiplier, uint256 totalETHFees);
	function getPricePrecisionDecimals() view external returns (uint256);
}

