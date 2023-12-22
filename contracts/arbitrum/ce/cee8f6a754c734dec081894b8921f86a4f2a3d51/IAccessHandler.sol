// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IAccessHandler {
    function changeAdmin(address) external;
    function pause() external;
    function unpause() external;
}

