// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IChef {
    function deposit(address acct, address host, uint256 amount) external;
    function withdraw(address acct, uint256 amount) external;

    function setHost(address acct, address host) external;

    function claim(address[] calldata accounts) external;

    function userInfo(address acct)
        external
        view
        returns (address host, uint256 amount, uint256 index, uint256 unclaimed);
}

