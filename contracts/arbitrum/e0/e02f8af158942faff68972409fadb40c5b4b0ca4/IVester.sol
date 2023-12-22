// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IVester {
    function claim(uint256[] calldata itemIndexes) external;

    function abort(uint256 itemIndex) external;
}

