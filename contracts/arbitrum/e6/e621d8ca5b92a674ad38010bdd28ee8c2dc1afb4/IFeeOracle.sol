// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

interface IFeeOracle {
    function getFee() external view returns (uint256);
}

