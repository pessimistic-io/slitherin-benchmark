// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IStakingProxy {
    function getBalance() external view returns (uint256);

    function withdraw(uint256 _amount) external;

    function stake() external;

    function distribute() external;
}

