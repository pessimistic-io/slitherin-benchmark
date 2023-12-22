//SPDX-License-Identifier: MIT
pragma solidity ^0.7.3;

interface IxTokenManager {
    /**
     * @dev Check if an address is a manager for a fund
     */
    function isManager(address manager, address fund)
        external
        view
        returns (bool);
}

