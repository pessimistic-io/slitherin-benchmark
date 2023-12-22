// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./Ownable.sol";
import "./ERC20.sol";

contract BFFT is ERC20, Ownable {

    constructor(uint256 _totalSupply) ERC20("BFFT", "BFFT") public {
        _mint(msg.sender, _totalSupply);
    }
}
