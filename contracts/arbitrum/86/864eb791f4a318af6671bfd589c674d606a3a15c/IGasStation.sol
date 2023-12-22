// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.8.15;


interface IGasStation {
    function addUser(address user) external;
    function recordUsage(address user) external;
}


