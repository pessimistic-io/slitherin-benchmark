// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC20.sol";
import "./Ownable.sol";

contract TestToken is ERC20, Ownable {
    /**
     * @notice Constructor.
     *
     * @param  to                           The address which will receive the initial supply of tokens.
     * @param  initialSupply                The initial supply of the total supply
     *
     */
    constructor(
        address to,
        uint256 initialSupply
    ) ERC20("Test Token", "TEST") {
        _mint(to, initialSupply);
    }

    /**
     * @notice Mint new tokens. Only callable by owner.
     *
     * @param  to  The address to receive minted tokens.
     * @param  amount     The number of tokens to mint.
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Destroys amount of tokens. Only callable by owner.
     *
     * @param  amount     The number of tokens to burn.
     */
    function burn(uint256 amount) external onlyOwner {
        _burn(_msgSender(), amount);
    }
}

