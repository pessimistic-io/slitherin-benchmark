// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {TickMath} from "./TickMath.sol";

interface IBunniToken {
    function tickLower() external view returns (int24);
    function tickUpper() external view returns (int24);
    function totalSupply() external view returns (uint256);
    function pool() external view returns (address);
    function hub() external view returns (address);
}

interface IUniV3Pool {
     function positions(bytes32 key)
        external
        view
        returns (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

        function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
}

contract BunniLens {
    using TickMath for int24;

    function tokenBalances(address bunniToken) external view returns (uint256 amount0, uint256 amount1, uint256 totalSupply) {
            address hub = IBunniToken(bunniToken).hub();
            address pool = IBunniToken(bunniToken).pool();
            int24 tickLower = IBunniToken(bunniToken).tickLower();
            int24 tickUpper = IBunniToken(bunniToken).tickUpper();
            (uint128 liquidity, , , , ) = IUniV3Pool(pool).positions(keccak256(abi.encodePacked(hub, tickLower, tickUpper)));
            (, int24 currentTick,,,,,) = IUniV3Pool(pool).slot0();

            (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
                TickMath.getSqrtRatioAtTick(currentTick),
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                liquidity
            );

            totalSupply = IBunniToken(bunniToken).totalSupply();
    }
}
