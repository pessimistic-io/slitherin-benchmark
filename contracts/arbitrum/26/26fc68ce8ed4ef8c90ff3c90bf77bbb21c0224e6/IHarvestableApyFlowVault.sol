// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface IHarvestableApyFlowVault {
    function harvest() external returns (uint256 assets);
}

