// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "./ERC20.sol";
import {Ownable} from "./Ownable.sol";

contract S5Token is ERC20, Ownable {
    uint256 private constant PRECISION = 1e18;
    uint256 public constant INITIAL_SUPPLY = PRECISION * 1000;

    /*
     * @param letter - The letter of the token. For example, if the token is S5TokenA, then the letter is "A".
     */
    constructor(string memory letter)
        ERC20(string.concat("S5Token", letter), string.concat("S5T", letter))
        Ownable(msg.sender)
    {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function mint(address to) external {
        _mint(to, PRECISION);
    }
}

