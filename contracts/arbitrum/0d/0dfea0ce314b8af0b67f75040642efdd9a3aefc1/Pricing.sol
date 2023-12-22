// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

library Pricing {
    function tokenPricing(uint tokenId) internal pure returns (uint){
        if (tokenId < 401) {
            return 1 ether;
        }

        return (tokenId - 301) / 100 * 1 ether * 3 / 100 + 1 ether;
    }
}

