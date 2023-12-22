// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IMining {
    function deposit(address _user, uint256 _amount) external;
    function withdraw(address _user, uint256 _amount) external;
}

