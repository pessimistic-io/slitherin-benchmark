// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.18;
import {MarketUtils} from "./IGMX.sol";

interface IGMXHedger {
    function hedge(
        int256 targetDelta,
        MarketUtils.MarketPrices calldata prices
    ) external returns (int256 deltaDiff);

    function sync() external returns (int256 collateralDiff);

    function getDelta() external view returns (int256);

    function getCollateralValue() external returns (uint256);

    function getRequiredCollateral() external returns (int256);
}

