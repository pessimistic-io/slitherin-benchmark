// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

interface IStargateFactory {    

    function allPoolsLength() external view returns (uint256);

    function allPools(uint256) external view returns (address);

    function getPool(uint256) external view returns (address);
}

