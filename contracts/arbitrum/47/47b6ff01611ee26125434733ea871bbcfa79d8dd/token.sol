// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

contract Token is ERC20, Ownable {
    constructor() ERC20("Simple AI", "SAI") {
        /*
            _mint is an internal function in ERC20.sol that is only called here,
            and CANNOT be called ever again
        */
        _mint(msg.sender, 1_000_000_000 * 1e18);
    }

    receive() external payable {

    }
}

