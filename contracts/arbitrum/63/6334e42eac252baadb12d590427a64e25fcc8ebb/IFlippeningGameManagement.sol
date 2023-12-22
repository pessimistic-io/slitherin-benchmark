//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./IERC20.sol";

interface IFlippeningGameManagement {
	event SetNonAlpha();
	event CancelGame();
	event ConvertFunds(IERC20 token, uint256 amount, uint24 poolFee, uint256 tokenPrice, uint256 ethAmount);
	event SetAmountMultiplier(uint256[] amounts, uint256[] multipliers);
	event SetRatioMultiplier(uint256[] ratios, uint256[] multipliers);
	event SetProximityMultiplier(uint256[] timeDiffs, uint256[] multipliers);

	function setNonAlpha() external;
	function cancelGame() external;

	// Note: price is a pool token price with 12 decimals (defined in PRECISION_DECIMALS of the UniswapHelper contract)
	function convertFunds(IERC20 token, uint256 amount, uint24 poolFee, uint256 tokenPrice) external returns (uint256 ethAmount);

	// Note: all multipliers are based on 1.0 equaling 10000 (defined in ONE_MULTIPLIER)
	function setAmountMultiplier(uint256[] calldata amounts, uint256[] calldata multipliers) external;
	function setRatioMultiplier(uint256[] calldata ratios, uint256[] calldata multipliers) external;
	function setProximityMultiplier(uint256[] calldata timeDiffs, uint256[] calldata multipliers) external;
}

