// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./IRamsesV2Pool.sol";
import "./RamsesV2MEVProtection.sol";

import "./CLMMPoolOracle.sol";

contract RamsesV2PoolOracle is CLMMPoolOracle {
    constructor(address admin, RamsesV2MEVProtection mevProtection_) CLMMPoolOracle(admin, mevProtection_) {}

    function getPriceAndOtherToken(
        address token,
        address pool
    ) public view override returns (uint256 priceX96, address tokenOut) {
        (uint160 sqrtPriceX96, , , , , , ) = IRamsesV2Pool(pool).slot0();
        priceX96 = FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, Q96);

        if (IRamsesV2Pool(pool).token1() == token) {
            tokenOut = IRamsesV2Pool(pool).token0();
            priceX96 = FullMath.mulDiv(Q96, Q96, priceX96);
        } else {
            tokenOut = IRamsesV2Pool(pool).token1();
        }
    }
}

