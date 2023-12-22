// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStrategy {
    function asset() external view returns (address);

    function vault() external view returns (address);

    function beforeDeposit() external;

    function deposited() external;

    function withdraw(uint256) external;

    function balanceOf() external view returns (uint256);

    function harvest() external;

    function exit() external;

    function panic() external;

    function pause() external;

    function unpause() external;

}

