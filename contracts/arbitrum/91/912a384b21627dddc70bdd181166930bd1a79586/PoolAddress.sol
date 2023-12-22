// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity =0.7.6;
library PoolAddress {
    bytes32 internal constant POOL_INIT_CODE_HASH = 0xe6b16e290cb376ebc5d1ae1a293763a28c2ee5a6829d50c61db25863d81e8613;

   
    function computeAddress(address factory, address token0,address token1,uint24 fee) internal pure returns (address pool) {
        require(token0 < token1);
        pool = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex'ff',
                        factory,
                        keccak256(abi.encode(token0, token1, fee)),
                        POOL_INIT_CODE_HASH
                    )
                )
            )
        );
    }
}
