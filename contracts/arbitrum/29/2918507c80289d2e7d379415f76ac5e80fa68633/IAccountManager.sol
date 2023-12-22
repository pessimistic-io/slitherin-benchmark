// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IAccountManager {
    function createAccount(string memory id) external returns (address _account);

    function getAccount(string memory id) external view returns (address _account);

    function isAccount(address _address) external view returns (bool, string memory);
}

