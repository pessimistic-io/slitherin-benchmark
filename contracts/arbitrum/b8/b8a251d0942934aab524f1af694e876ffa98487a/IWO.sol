// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Crowdsale.sol";

contract IWO is Crowdsale {
	constructor(
		uint256 rate,
		address payable wallet,
		IMintableERC20 token,
		address _oracle
	) Crowdsale(rate, wallet, token, _oracle) {}
}

