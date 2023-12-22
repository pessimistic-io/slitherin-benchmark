//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

interface IRangeValueGenerator {
    error AllValuesGenerated();

    function min() external view returns (uint256);

    function max() external view returns (uint256);
}

