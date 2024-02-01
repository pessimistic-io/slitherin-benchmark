// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IWhitelistRegistry {
    function status(address addr) external view returns(uint256);
}

