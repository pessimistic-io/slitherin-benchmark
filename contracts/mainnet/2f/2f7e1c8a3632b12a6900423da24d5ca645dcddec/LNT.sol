// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.11;

import "./ERC20.sol";
import "./ERC20Burnable.sol";

/**
 *  @title Laconic Network Token
 *  @notice A fixed supply, burnable ERC20 token. Supply of 129,600 tokens
 *   is based on the number of calendar years in a Chinese Cosmic year:
 *   https://en.wikipedia.org/wiki/Cosmic_year_(Chinese_astrology)
 */
contract LNT is ERC20("Laconic Network Token", "LNT"), ERC20Burnable {
    constructor(address owner) {
        _mint(owner, 129_600 ether);
    }
}

