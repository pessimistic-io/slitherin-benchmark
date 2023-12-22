// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ITradeAccess {

    function userState(address user) external view returns(uint8);

    function setGlobalAdmin(address user) external;
    function removeGlobalAdmin(address user) external;
    function banUser(address user) external;
}

