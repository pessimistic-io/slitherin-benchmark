// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./Ownable.sol";
import "./ERC20.sol";

contract CBT is ERC20, Ownable {

    constructor(uint256 _totalMinted) ERC20("CBT", "CBT") public {
        _mint(msg.sender, _totalMinted);
    }
}
