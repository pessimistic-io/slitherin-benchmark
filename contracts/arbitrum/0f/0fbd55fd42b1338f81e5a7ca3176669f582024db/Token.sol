// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./ERC20.sol";
import "./Ownable.sol";

contract Token is ERC20, Ownable {
	constructor(
		string memory name, 
		string memory symbol, 
		address supplyReceiver, 
		uint supply
	) 
		public 
		ERC20(name, symbol) 
	{
		_mint(supplyReceiver, supply);
	}

	function mint(address _to, uint256 _amount) public onlyOwner {
		_mint(_to, _amount);
	}

	function burn(uint256 _amount) public {
		_burn(msg.sender, _amount);
	}

	function safeTokenTransfer(address _to, uint256 _amount) public onlyOwner {
		uint256 tokenBal = balanceOf(address(this));
		if (_amount > tokenBal) _transfer(address(this), _to, tokenBal);
		else _transfer(address(this), _to, _amount);
	}
}


