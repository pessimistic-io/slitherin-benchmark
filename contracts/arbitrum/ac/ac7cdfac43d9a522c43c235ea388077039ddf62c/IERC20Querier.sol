// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IERC20Querier {
    function decimals() external view returns (uint256);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function totalSupply() external view returns (uint256);
}

