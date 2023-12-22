// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "./ERC20.sol";

contract BPanda is Context, ERC20 {

	constructor(uint256 _supply) ERC20("BabyPanda", "BPanda") {
		_mint(msg.sender, _supply);
	}
}
