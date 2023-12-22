// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./token_ERC20.sol";

contract StakeToken is ERC20 {
	address public minter;

	constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
		minter = msg.sender;
	}

	modifier onlyMinter() {
		require(minter == msg.sender);
		_;
	}

	function mint(address to, uint256 value) public onlyMinter returns (bool) {
		_mint(to, value);
		return true;
	}

	function burn(address to, uint256 value) public onlyMinter returns (bool) {
		_burn(to, value);
		return true;
	}
}

