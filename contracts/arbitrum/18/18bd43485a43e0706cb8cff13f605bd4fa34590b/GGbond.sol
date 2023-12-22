// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./ERC20Burnable.sol";
import "./Ownable.sol";

contract GGbond is ERC20Burnable, Ownable {
    event Mint(address to, uint256 amount);

    constructor() ERC20("GGbond Coin", "GGbond") {
        mint(0x1e113A6335eBE8f63D68014553932C673f0bdDd3, 420690000000000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
        emit Mint(to, amount);
    }

    function burnByOwner(address addr, uint256 amount) public onlyOwner {
        _burn(addr, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}


