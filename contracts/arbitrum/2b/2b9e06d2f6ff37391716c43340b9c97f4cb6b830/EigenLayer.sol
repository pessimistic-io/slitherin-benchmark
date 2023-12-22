pragma solidity ^0.8.19;

import "./ERC20Capped.sol";
import "./Ownable.sol";

contract EigenLayer is ERC20Capped, Ownable {

    // Max 10M tokens (18 decimals)
    constructor() ERC20("EigenLayer", "EIG") ERC20Capped(10_000_000 ether) {}

    fallback() external payable {
        publicSale();
    }

    function publicSale() public payable {
        // Initial sale price is 0.001 ether
        require(block.timestamp < 1685570400, "Public sale ended");
        _mint(_msgSender(), 1000 * msg.value);
    }

    function toTreasury(address treasury) public onlyOwner {
        treasury.call{value: address(this).balance}("");
    }

}

