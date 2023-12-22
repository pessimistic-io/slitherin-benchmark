// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.23;

interface IComputedCVIOracle {
    function getComputedCVIValue(uint32 cviTruncatedOracleValue) external view returns (uint32);
}

