// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./draft-ERC20Permit.sol";

contract AFC is ERC20, ERC20Burnable, Pausable, Ownable, ERC20Permit {
	constructor(string memory name, string memory symbol) ERC20(name, symbol) ERC20Permit(name) {}

	function decimals() public view virtual override returns (uint8) {
		return 0;
	}

	function pause() public onlyOwner {
		_pause();
	}

	function unpause() public onlyOwner {
		_unpause();
	}

	function mint(address to, uint256 amount) public onlyOwner {
		_mint(to, amount);
	}

	function _beforeTokenTransfer(address from, address to, uint256 amount) internal override whenNotPaused {
		super._beforeTokenTransfer(from, to, amount);
	}
}

