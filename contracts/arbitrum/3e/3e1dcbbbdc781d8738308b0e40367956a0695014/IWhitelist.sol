// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IWhitelist {
    function isWhitelists(address) external view returns (bool);
}

