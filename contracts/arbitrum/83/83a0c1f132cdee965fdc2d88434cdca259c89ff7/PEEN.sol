// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./ERC20Burnable.sol";

contract PEEN is Ownable, ERC20Burnable {
 constructor() Ownable() ERC20("Peen", "PEEN") {
    // SHITCOINS ONLY WALLET
    address wallet = 0x7C016E48345A2B54a628EDB13b722bc3B0196bd5;
    uint256 SUPPLY = 1000000000;

    _mint(wallet, SUPPLY * 10 ** decimals());

    // renounce Ownership
    renounceOwnership();
 }

 function decimals() public view virtual override returns (uint8) {
    return 9;
 }
}

