// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ERC20} from "./ERC20.sol";

contract TokenSaleReceipt is ERC20 {
    error Unauthorized();

    mapping(address => bool) public exec;

    constructor() ERC20("Rodeo Sale Receipt", "srRDO", 18) {
        exec[msg.sender] = true;
    }

    function setExec(address who, bool can) public {
        if (!exec[msg.sender]) revert Unauthorized();
        exec[who] = can;
    }

    function mint(address to, uint256 amount) public {
        if (!exec[msg.sender]) revert Unauthorized();
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        if (!exec[msg.sender]) revert Unauthorized();
        _burn(from, amount);
    }
}

