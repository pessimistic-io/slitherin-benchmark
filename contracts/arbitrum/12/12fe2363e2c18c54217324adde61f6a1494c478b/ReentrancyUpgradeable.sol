// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

abstract contract ReentrancyUpgradeable {
    /// @dev simple re-entrancy check
    uint256 internal _unlocked;

    modifier lock() {
        require(_unlocked == 1, "Reentrant call");
        _unlocked = 2;
        _;
        _unlocked = 1;
    }

    function ReentrancyUpgradeable__init() public {
        _unlocked = 1;
    }
}

