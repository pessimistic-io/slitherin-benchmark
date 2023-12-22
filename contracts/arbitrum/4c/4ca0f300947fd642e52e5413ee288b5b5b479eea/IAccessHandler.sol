// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IAccessHandler {
    function addAdmin(address) external;
    function removeAdmin(address) external;
    function pause() external;
    function unpause() external;
}

