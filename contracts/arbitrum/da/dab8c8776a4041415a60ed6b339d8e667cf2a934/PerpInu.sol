//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "./ERC20.sol";
import "./Ownable.sol";

contract PerpInu is ERC20, Ownable {
    constructor() ERC20("Perp Inu", "PERPI") {
        _mint(msg.sender, 1_000_000 * 10 ** 18);
    }
}
