// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import {yVault} from "./yVault.sol";

contract BTCVault is yVault {
	constructor(
		address _token,
		address _controller,
		string memory _name,
		string memory _symbol
	) yVault(_token, _controller, _name, _symbol) {}
}

