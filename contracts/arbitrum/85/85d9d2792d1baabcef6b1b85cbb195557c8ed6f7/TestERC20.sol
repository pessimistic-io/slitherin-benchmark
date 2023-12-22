// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./ERC20.sol";

contract ZooDAOToken is ERC20 {
    constructor() ERC20('ZooDAO', 'ZOO') public {}

	function mint(uint256 amount) public {
		_mint(msg.sender, amount);
	}
}

