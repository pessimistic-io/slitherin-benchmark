// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./Crowdsale.sol";

contract IWOChoke is Crowdsale {
	constructor(
		address payable wallet,
		IMintableERC20 token,
		IERC20 whitelistToken,
		uint256 whitelistTokenAmount,
		address _oracle,
		uint256 startDate,
		uint256 endDate
	)
		Crowdsale(
			wallet,
			token,
			whitelistToken,
			whitelistTokenAmount,
			_oracle,
			startDate,
			endDate
		)
	{}
}

