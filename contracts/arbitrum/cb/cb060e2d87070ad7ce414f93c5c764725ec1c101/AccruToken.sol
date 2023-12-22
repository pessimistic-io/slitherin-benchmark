// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC20.sol";
import "./Ownable.sol";

contract AccruToken is ERC20, Ownable {

    uint256 public constant MAX_SUPPLY = 100_000_000_000 * 10 ** 18;

    /**
     * @notice Constructor.
     *
     * @param  to The address which will receive the initial supply of tokens.
     *
     */
    constructor(address to) ERC20("Accru Token", "ACCRU") {
        _mint(to, MAX_SUPPLY);
    }

    /**
     * @notice Destroys amount of tokens. Only callable by owner.
     *
     * @param  amount The number of tokens to burn.
     */
    function burn(uint256 amount) external onlyOwner {
        _burn(_msgSender(), amount);
    }
}

