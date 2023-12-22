// SPDX-License-Identifier: NONE
pragma solidity 0.8.10;

library LibPrices {
    function getPerDollarTokenPrice(uint256 amount, uint256 tokenPrice)
        internal
        pure
        returns (uint256)
    {
        return ((amount * 1 ether) / uint256(tokenPrice));
    }
}

