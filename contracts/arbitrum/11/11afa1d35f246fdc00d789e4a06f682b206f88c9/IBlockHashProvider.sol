// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

interface IBlockHashProvider {
    function blockHashStored(bytes32 _hash) external view returns (bool _result);
}

