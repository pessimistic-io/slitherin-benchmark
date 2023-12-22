// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IInsuranceFund {
    function withdraw(uint256 _amount, address _user, address _token) external;

    function deposit(uint256 _amount, address _user, address _token) external;
}

