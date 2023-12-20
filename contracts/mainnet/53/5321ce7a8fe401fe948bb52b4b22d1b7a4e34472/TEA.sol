// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract TEA is ERC20, Ownable, ERC20Burnable {
    event tokensBurned(address indexed owner, uint256 amount, string message);
    event tokensMinted(address indexed owner, uint256 amount, string message);

    constructor() ERC20("TEA", "TEA") {
        _mint(msg.sender, 8888888888 * 10**decimals());
        emit tokensMinted(msg.sender, 8888888888 * 10**decimals(), "Initial supply of tokens minted.");
    }

    function burn(uint256 amount) public override onlyOwner {
        _burn(msg.sender, amount);
        emit tokensBurned(msg.sender, amount, "Tokens burned.");
    }
}
