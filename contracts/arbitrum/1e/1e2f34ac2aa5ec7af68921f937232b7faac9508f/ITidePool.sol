// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

interface ITidePool {

    event Deposited(address owner, uint256 liquidity);
    event Withdraw(address owner, uint256 amount0, uint256 amount1);
    event Rerange();
    event Rebalance();

    struct MintCallbackData {
        address payer;
    }

    struct SwapCallbackData {
        bool zeroForOne;
    }

    function deposit(uint256 amount0, uint256 amount1) external returns (uint128 liquidity);

    function withdraw() external;

    function rerange() external;

    function rebalance() external;
}
