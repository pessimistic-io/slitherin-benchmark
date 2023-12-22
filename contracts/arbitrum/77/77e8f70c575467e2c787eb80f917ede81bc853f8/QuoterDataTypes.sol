//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./libraries_DataTypes.sol";

struct OpeningCostParams {
    Symbol symbol; // InstrumentStorage to be used
    uint256 quantity; // Size of the position
    uint256 collateralSlippage; // How much add to minCollateral and remove from maxCollateral to avoid issues with min/max debt. In %, 1e18 == 100%
    uint24 uniswapFee; // The fee to be used for the quote
}

struct ModifyCostParams {
    PositionId positionId;
    int256 quantity; // How much the size of the position should change by
    uint256 collateralSlippage; // How much add to minCollateral and remove from maxCollateral to avoid issues with min/max debt. In %, 1e18 == 100%
    uint24 uniswapFee; // The fee to be used for the quote
}

// What does the signed cost mean?
// In general, it'll be negative when quoting cost to open/increase, and positive when quoting cost to close/decrease.
// However, there are certain situations where that general rule may not hold true, for example when the qty delta is small and the collateral delta is big.
// Scenarios include:
//      * increase position by a tiny bit, but add a lot of collateral at the same time (aka. burn existing debt)
//      * decrease position by a tiny bit, withdraw a lot of excess equity at the same time (aka. issue new debt)
// For this reason, we cannot get rid of the signing, and make assumptions about in which direction the cost will go based on the qty delta alone.
// The effect (or likeliness of this coming into play) is much greater when the funding currency (quote) has a high interest rate.
struct ModifyCostResult {
    int256 spotCost; // The current spot cost of a given position quantity
    int256 cost; // See comment above for explanation of why the cost is signed.
    int256 financingCost; // The cost to increase/decrease collateral. We need to return this breakdown of cost so the UI knows which values to pass to 'modifyCollateral'
    int256 debtDelta; // if negative, it's the amount repaid. If positive, it's the amount of new debt issued.
    int256 collateralUsed; // Collateral used to open/increase position with returned cost
    int256 minCollateral; // Minimum collateral needed to perform modification. If negative, it's the MAXIMUM amount that CAN be withdrawn.
    int256 maxCollateral; // Max collateral allowed to open/increase a position. If negative, it's the MINIMUM amount that HAS TO be withdrawn.
    uint256 underlyingDebt; // Value of debt 1:1 with real underlying (Future Value)
    uint256 underlyingCollateral; // Value of collateral in debt terms
    uint256 liquidationRatio; // The ratio at which a position becomes eligible for liquidation (underlyingCollateral/underlyingDebt)
    uint256 fee;
    uint128 minDebt;
    uint256 baseLendingLiquidity; // Deprecated, value's now always set to type(uint128).max
    uint256 quoteLendingLiquidity; // Deprecated, value's now always set to type(uint128).max
    // relevant to closing only
    bool needsBatchedCall;
}

struct DeliveryCostResult {
    uint256 deliveryCost; // total delivery cost (debt + existing fees + delivery fee)
    uint256 deliveryFee; // fee charged for physical delivery
}

struct PositionStatus {
    uint256 spotCost; // The current spot cost of a given position quantity
    uint256 underlyingDebt; // Value of debt 1:1 with real underlying (Future Value)
    uint256 underlyingCollateral; // Value of collateral in debt terms
    uint256 liquidationRatio; // The ratio at which a position becomes eligible for liquidation (underlyingCollateral/underlyingDebt)
    bool liquidating; // When true, no actions are allowed over the position
}

