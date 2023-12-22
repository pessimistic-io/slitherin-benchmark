// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

interface IMuxOrderBook {

    struct PositionOrderExtra {
        // tp/sl strategy
        uint96 tpPrice; // take-profit price. decimals = 18. only valid when flags.POSITION_TPSL_STRATEGY.
        uint96 slPrice; // stop-loss price. decimals = 18. only valid when flags.POSITION_TPSL_STRATEGY.
        uint8 tpslProfitTokenId; // only valid when flags.POSITION_TPSL_STRATEGY.
        uint32 tpslDeadline; // only valid when flags.POSITION_TPSL_STRATEGY.
    }

    function placePositionOrder3(
        bytes32 subAccountId,
        uint96 collateralAmount, // erc20.decimals
        uint96 size, // 1e18
        uint96 price, // 1e18
        uint8 profitTokenId,
        uint8 flags,
        uint32 deadline, // 1e0
        bytes32 referralCode,
        PositionOrderExtra memory extra
    ) external payable;

    /**
     * @notice Add/remove liquidity. called by Liquidity Provider.
     *
     *         Can be filled after liquidityLockPeriod seconds.
     * @param  assetId   asset.id that added/removed to.
     * @param  rawAmount asset token amount. decimals = erc20.decimals.
     * @param  isAdding  true for add liquidity, false for remove liquidity.
     */
    function placeLiquidityOrder(
        uint8 assetId,
        uint96 rawAmount, // erc20.decimals
        bool isAdding
    ) external payable;

}

