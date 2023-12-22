// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./Ownable.sol";
import "./ERC20.sol";

contract BCToken is ERC20, Ownable {

    constructor(uint256 _totalMinted) ERC20("BCARD", "BCARD") public {
        _mint(msg.sender, _totalMinted);
    }
}
