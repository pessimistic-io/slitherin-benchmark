// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "./ERC20.sol";
import "./Ownable.sol";
import "./Multicall.sol";

/// @title Moola's ERC20 token
contract MoolaToken is ERC20, Ownable, Multicall {
    constructor() ERC20("Moola", "MOOLA") {
        _mint(msg.sender, 7_777_777_777 ether);
    }

    /**
     * @dev This function is here to ensure BEP-20 compatibility
     */
    function getOwner() external view returns (address) {
        return owner();
    }
}

