pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

contract PArbiTen is ERC20('PArbiTen', 'PArbiTen'), Ownable {
    constructor() {
        _mint(msg.sender, 1040 ether);
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
