// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

library Price {
    uint256 internal constant PRICE_PRECISION = 10 ** 18;

    function getPrice(
        uint256 initPrice,
        uint256 postSupply
    ) internal pure returns (uint256) {
        return ((((initPrice + postSupply * PRICE_PRECISION) / 16) *
            ((initPrice + postSupply * PRICE_PRECISION) / 16)) /
            PRICE_PRECISION +
            initPrice);
    }
}

