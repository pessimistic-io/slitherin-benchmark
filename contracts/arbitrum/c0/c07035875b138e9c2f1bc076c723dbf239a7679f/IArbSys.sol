// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

interface IArbSys {
    function arbBlockNumber() external view returns (uint256);

    function arbBlockHash(uint256 arbBlockNum) external view returns (bytes32);
}
