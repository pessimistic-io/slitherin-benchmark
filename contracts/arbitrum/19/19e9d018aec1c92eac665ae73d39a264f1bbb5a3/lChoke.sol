// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./ERC4626.sol";

contract LChoke is ERC4626 {
	constructor(
		string memory _name,
		string memory _symbol,
		address _underlying
	) ERC20(_name, _symbol) ERC4626(IERC20(_underlying)) {}
}

