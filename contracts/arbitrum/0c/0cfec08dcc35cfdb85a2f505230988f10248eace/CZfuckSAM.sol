// SPDX-License-Identifier: AGPL-3.0-or-later

/*

https://t.me/czfucksam
https://twitter.com/czfucksam

FTT to 0
BNB to 10k

*/

pragma solidity ^0.8.13;

import "./ERC20.sol";
import "./Ownable.sol";

contract CZfuckSAM is ERC20, Ownable {

    constructor() ERC20("CZ fuck SAM", "CZFUCKSAM") {
        _mint(msg.sender, 1_000_000 * 10**18);
    }

    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }

}
