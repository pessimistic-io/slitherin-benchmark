//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface IHunchGame {

	// Note: Amount multiplier is based on 1.0 equaling 10000 (defined in ONE_MULTIPLIER),
	// sees parameter consist of fees paid to treasury in ETH
	event ClosePositionTicket(address indexed account, uint256 indexed ticketId, uint256 indexed positionTokenId, 
		uint256 ethAmount, uint256 fees, uint256 ticketETHAmount, uint256 ticketMultipliedETHAmount, uint256 amountMultiplier);
	
	function gameId() view external returns (uint256 id);

	function setTreasury(address payable treasury) external;
}

