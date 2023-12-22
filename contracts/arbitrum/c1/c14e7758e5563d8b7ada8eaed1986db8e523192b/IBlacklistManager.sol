// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;


interface IBlacklistManager {
    function isBlacklist(address _account) external view returns (bool);

    function validateCaller(address _account) external view;
}
