//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.2;

interface IFeeReceiver {
    function deposit(address _token, uint256 _amount) external;
}

