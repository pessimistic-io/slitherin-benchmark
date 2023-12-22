// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IRateOracle {
    function getIBTRate() external view returns (uint256);
}

