// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.17;
pragma abicoder v2;

import "./IAlgebraFactory.sol";
import "./IAlgebraMintCallback.sol";
import "./TickMath.sol";

import "./PoolAddress.sol";
import "./CallbackValidation.sol";
import "./LiquidityAmounts.sol";

import "./PeripheryPayments.sol";
import "./PeripheryImmutableState.sol";

/// @title Liquidity management functions
/// @notice Internal functions for safely managing liquidity in Algebra
/// @dev Credit to Uniswap Labs under GPL-2.0-or-later license:
/// https://github.com/Uniswap/v3-periphery
abstract contract LimitOrderManagment is
    IAlgebraMintCallback,
    PeripheryImmutableState,
    PeripheryPayments
{
    struct MintCallbackData {
        PoolAddress.PoolKey poolKey;
        address payer;
    }

    /// @inheritdoc IAlgebraMintCallback
    function algebraMintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));
        CallbackValidation.verifyCallback(poolDeployer, decoded.poolKey);

        if (amount0Owed > 0)
            pay(decoded.poolKey.token0, decoded.payer, msg.sender, amount0Owed);
        if (amount1Owed > 0)
            pay(decoded.poolKey.token1, decoded.payer, msg.sender, amount1Owed);
    }

    /// @notice Add liquidity to an initialized pool
    function createLimitOrder(
        address token0,
        address token1,
        int24 tick,
        uint128 amount
    ) internal returns (IAlgebraPool pool, bool depositedToken) {
        PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({
            token0: token0,
            token1: token1
        });

        pool = IAlgebraPool(PoolAddress.computeAddress(poolDeployer, poolKey));

        (, uint256 amount1, ) = pool.mint(
            msg.sender,
            address(this),
            tick,
            tick,
            amount,
            abi.encode(MintCallbackData({poolKey: poolKey, payer: msg.sender}))
        );
        depositedToken = amount1 > 0;
    }
}

