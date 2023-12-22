// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

interface ISwapper {
	function swap(
        address inToken,
        address outToken,
        uint256 inAmount,
        address caller,
        bytes calldata data
    ) external payable returns (uint256);
}


