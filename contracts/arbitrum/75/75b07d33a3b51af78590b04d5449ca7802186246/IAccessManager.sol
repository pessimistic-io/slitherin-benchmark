// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IAccessManager {
    function hasAccess(address user) external view returns (bool);
    function participate(address user) external;
}
