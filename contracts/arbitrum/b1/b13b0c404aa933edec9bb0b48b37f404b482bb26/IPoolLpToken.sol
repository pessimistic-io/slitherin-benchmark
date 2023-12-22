// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.15;

interface IPoolLpToken {
    function totalSupply() external view returns (uint256);

    function totalLiquidity() external view returns (uint256);
}

