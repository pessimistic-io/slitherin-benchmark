// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IHarvester {
    function getUserDepositCap(address user)
        external
        view
        returns (uint256 cap);
}

