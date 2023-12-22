pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract P10SHARE is ERC20('P10SHARE', 'P10SHARE'), Ownable {
    constructor() {
        _mint(msg.sender, 6 ether);
    }

    function mint(address account, uint amount) external onlyOwner {
        _mint(account, amount);
    }

    function burn(address account, uint amount) external onlyOwner {
        _burn(account, amount);
    }

	function decimals() public view override returns (uint8) {
		return 18;
	}
}
