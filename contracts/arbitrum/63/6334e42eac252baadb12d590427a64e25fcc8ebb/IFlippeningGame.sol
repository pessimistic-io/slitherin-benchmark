//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface IFlippeningGame  {

	// Note: In all events, marketCapRatio is the market cap btc/eth ratio with 1.0 defined as 10000,
	// and all multiplier (amount, ratio and distance) are based on 1.0 equaling 10000 (defined in ONE_MULTIPLIER)
	// Fees parameters are fees paid to treasury in ETH

	event BuyETHTicket(address indexed account, uint256 indexed ticketId, uint256 flippeningDate, uint256 marketCapRatio,
		uint256 ethAmount, uint256 fees, uint256 ticketETHAmount, uint256 ticketMultipliedETHAmount, uint256 amountMultiplier);
	event BuyPositionETHTicket(address indexed account, uint256 indexed ticketId, uint256 flippeningDate, uint256 marketCapRatio,
		uint256 indexed positionTokenId, uint256 ethAmount, uint256 fees, uint256 ticketETHAmount, 
		uint256 ticketMultipliedETHAmount, uint256 amountMultiplier);
	event BuyPositionTicket(address indexed account, uint256 indexed ticketId, uint256 flippeningDate, uint256 marketCapRatio, 
		uint256 indexed positionTokenId);

	event Flip(uint256 flippeningDate);
	event ClaimWin(address indexed account, uint256 ticketId, uint256 multipliedAmount, uint256 ratioMultiplier, 
		uint256 distanceMultiplier);
	event CollectRewards(uint256 ticketId, uint256 positionTokenId, uint256 ethAmount);
	event ClaimReward(address indexed account, uint256 ticketId, uint256 reward, 
		uint256 multipliedAmount, uint256 totalReward, uint256 totalClaimedMultipliedAmount);

	function buyETHTicket(uint256 flippeningDate) external payable returns (uint256 ticketId);

	// Note: price values are pool token prices with 12 decimals (defined in PRECISION_DECIMALS of the UniswapHelper contract)
	function buyPositionETHTicket(uint256 positionTokenId, uint256 flippeningDate, uint256 token0ETHPrice, uint256 token1ETHPrice) external returns (uint256 ticketId);

	function buyPositionTicket(uint256 positionTokenId, uint256 flippeningDate) external returns (uint256 ticketId);

	// Note: price values are pool token prices with 12 decimals (defined in PRECISION_DECIMALS of the UniswapHelper contract)
	function closePositionTicket(uint256 ticketId, uint256 token0ETHPrice, uint256 token1ETHPrice) external;

	function flip() external;

	// Note: price values are pool token prices with 12 decimals (defined in PRECISION_DECIMALS of the UniswapHelper contract),
	function claimWin(uint256 ticketId, uint256 token0ETHPrice, uint256 token1ETHPrice) external;

	function collectRewards(uint256 maxPositionsToCollect) external returns (uint256 findersFee);
	function claimReward(uint256 ticketId) external;

	// Multiplier is based on 1.0 equaling 10000 (defined in ONE_MULTIPLIER)
	function getMultipliedETHAmount(uint256 ethAmount, uint256 /*ticketId*/) external view returns (uint256 multipliedETHAmount, uint256 multiplier);

	// Note: ratio is the market cap btc/eth ratio with 1.0 defined as 10000
	// Multiplier is based on 1.0 equaling 10000 (defined in ONE_MULTIPLIER)
	function getRatioMultiplier(uint256 ratio) external view returns (uint256 multiplier);

	function getFlippeningDistanceMultiplier(uint256 betDate) external view returns (uint256);
	function canClaimReward() external view returns (bool);

	// Note: all multipliers are based on 1.0 equaling 10000 (defined in ONE_MULTIPLIER)
	// Strength is a virtual amount based on initial eth amount in the ticket, multiplied by all mutlipliers	
	function strengthOf(uint256 ticketId) external view returns (uint256 strength, uint256 amountMultiplier, uint256 ratioMultiplier, uint256 proximityMultiplier);
}
