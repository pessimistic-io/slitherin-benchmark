//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./ERC20.sol";

contract CZZToken is ERC20 {

    uint8 private _decimals = 18;
    uint256 private initSupply = 180000;

	constructor() ERC20("ChainZZ Token","CZZ") {
		_setupDecimals(_decimals);
	    _mint(msg.sender, initSupply * 10 ** _decimals);
	}
	
}
