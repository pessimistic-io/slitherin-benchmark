// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ICrv2PoolOracle {
    function getUsdcPrice() external view returns (uint256);

    function getUsdtPrice() external view returns (uint256);

    function getLpVirtualPrice() external view returns (uint256);

    function getLpPrice() external view returns (uint256);
}

