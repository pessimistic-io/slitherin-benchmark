// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "./IRamsesV2Pool.sol";
import "./FixedPoint128.sol";
import "./FullMath.sol";

import "./INonfungiblePositionManager.sol";

import "./PositionKey.sol";

/// @dev Splitting the contract because it's over the max code size
library PositionManagerAux {
    /// @notice Emitted when liquidity is decreased for a position NFT
    /// @param tokenId The ID of the token for which liquidity was decreased
    /// @param liquidity The amount by which liquidity for the NFT position was decreased
    /// @param amount0 The amount of token0 that was accounted for the decrease in liquidity
    /// @param amount1 The amount of token1 that was accounted for the decrease in liquidity
    event DecreaseLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    /// @notice Emitted when tokens are collected for a position NFT
    /// @dev The amounts reported may not be exactly equivalent to the amounts transferred, due to rounding behavior
    /// @param tokenId The ID of the token for which underlying tokens were collected
    /// @param recipient The address of the account that received the collected tokens
    /// @param amount0 The amount of token0 owed to the position that was collected
    /// @param amount1 The amount of token1 owed to the position that was collected
    event Collect(uint256 indexed tokenId, address recipient, uint256 amount0, uint256 amount1);

    function decreaseLiquidity(
        INonfungiblePositionManager.Position storage position,
        IRamsesV2Pool pool,
        INonfungiblePositionManager.DecreaseLiquidityParams calldata params
    ) external returns (uint256 amount0, uint256 amount1) {
        require(params.liquidity > 0);

        uint128 positionLiquidity = position.liquidity;
        require(positionLiquidity >= params.liquidity);

        (amount0, amount1) = pool.burn(params.tokenId, position.tickLower, position.tickUpper, params.liquidity);

        require(amount0 >= params.amount0Min && amount1 >= params.amount1Min, 'Price slippage check');

        bytes32 positionKey = PositionKey.compute(
            address(this),
            params.tokenId,
            position.tickLower,
            position.tickUpper
        );
        // this is now updated to the current transaction
        (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , , ) = pool.positions(positionKey);

        position.tokensOwed0 +=
            uint128(amount0) +
            uint128(
                FullMath.mulDiv(
                    feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                    positionLiquidity,
                    FixedPoint128.Q128
                )
            );
        position.tokensOwed1 +=
            uint128(amount1) +
            uint128(
                FullMath.mulDiv(
                    feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                    positionLiquidity,
                    FixedPoint128.Q128
                )
            );

        position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
        position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        // subtraction is safe because we checked positionLiquidity is gte params.liquidity
        position.liquidity = positionLiquidity - params.liquidity;

        emit DecreaseLiquidity(params.tokenId, params.liquidity, amount0, amount1);
    }

    function collect(
        INonfungiblePositionManager.Position storage position,
        IRamsesV2Pool pool,
        INonfungiblePositionManager.CollectParams calldata params
    ) external returns (uint256 amount0, uint256 amount1) {
        require(params.amount0Max > 0 || params.amount1Max > 0);
        // allow collecting to the nft position manager address with address 0
        address recipient = params.recipient == address(0) ? address(this) : params.recipient;

        (uint128 tokensOwed0, uint128 tokensOwed1) = (position.tokensOwed0, position.tokensOwed1);

        // trigger an update of the position fees owed and fee growth snapshots if it has any liquidity
        if (position.liquidity > 0) {
            pool.burn(params.tokenId, position.tickLower, position.tickUpper, 0);
            (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , , ) = pool.positions(
                PositionKey.compute(address(this), params.tokenId, position.tickLower, position.tickUpper)
            );

            tokensOwed0 += uint128(
                FullMath.mulDiv(
                    feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
                    position.liquidity,
                    FixedPoint128.Q128
                )
            );
            tokensOwed1 += uint128(
                FullMath.mulDiv(
                    feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
                    position.liquidity,
                    FixedPoint128.Q128
                )
            );

            position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
            position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
        }

        // compute the arguments to give to the pool#collect method
        (uint128 amount0Collect, uint128 amount1Collect) = (
            params.amount0Max > tokensOwed0 ? tokensOwed0 : params.amount0Max,
            params.amount1Max > tokensOwed1 ? tokensOwed1 : params.amount1Max
        );

        // the actual amounts collected are returned
        (amount0, amount1) = pool.collect(
            recipient,
            params.tokenId,
            position.tickLower,
            position.tickUpper,
            amount0Collect,
            amount1Collect
        );

        // sometimes there will be a few less wei than expected due to rounding down in core, but we just subtract the full amount expected
        // instead of the actual amount so we can burn the token
        (position.tokensOwed0, position.tokensOwed1) = (tokensOwed0 - amount0Collect, tokensOwed1 - amount1Collect);

        emit Collect(params.tokenId, recipient, amount0Collect, amount1Collect);
    }
}

