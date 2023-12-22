// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./ERC20.sol";
import "./Ownable.sol";

contract AlphaDoge is ERC20, Ownable {
    constructor() ERC20("Alpha Doge", "ADC") {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        (bool os, ) = payable(owner()).call{value: balance}("");
        require(os);
    }

    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        return _dogeTransfer(_msgSender(), to, amount);
    }

    function _dogeTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        _transfer(sender, recipient, amount);
        return true;
    }

    receive() external payable {}
}

