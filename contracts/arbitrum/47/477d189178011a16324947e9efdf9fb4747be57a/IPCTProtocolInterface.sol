// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;
pragma abicoder v2;

interface IPCTProtocolInterface {
    function investedToken() external view returns (address);

    function protocolToken() external view returns (address);

    function principal() external view returns (uint256);

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function withdrawRewards() external returns (uint256);
}

