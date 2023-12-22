// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IMetaPool} from "./IMetaPool.sol";
import {ICryptoPool} from "./kokonut-swap_ICryptoPool.sol";
import {IBasePool} from "./IBasePool.sol";
import {IRegistry} from "./kokonut-swap_IRegistry.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

library LibKokonutSwap {
    using LibAsset for address;

    function getPoolAddress(bytes memory poolData) private pure returns (address poolAddress) {
        assembly {
            poolAddress := shr(96, mload(add(poolData, 32)))
        }
    }

    function swapKokonutBase(Hop memory h) internal returns (uint256 amountOut) {
        uint256 i;
        uint256 l = h.path.length;

        for (i = 0; i < l - 1; ) {
            uint256 amountIn = i == 0 ? h.amountIn : amountOut;
            address poolAddress = getPoolAddress(h.poolDataList[i]);
            h.path[i].approve(poolAddress, amountIn);
            (uint256 tokenIndexFrom, uint256 tokenIndexTo) = IRegistry(h.addr).getCoinIndices(
                poolAddress,
                h.path[i],
                h.path[i + 1]
            );
            (amountOut, ) = IBasePool(poolAddress).exchange(tokenIndexFrom, tokenIndexTo, amountIn, 0, new bytes(0));

            unchecked {
                i++;
            }
        }
    }

    function swapKokonutCrypto(Hop memory h) internal returns (uint256 amountOut) {
        uint256 i;
        uint256 l = h.path.length;

        for (i = 0; i < l - 1; ) {
            uint256 amountIn = i == 0 ? h.amountIn : amountOut;
            address poolAddress = getPoolAddress(h.poolDataList[i]);
            h.path[i].approve(poolAddress, amountIn);
            (uint256 tokenIndexFrom, uint256 tokenIndexTo) = IRegistry(h.addr).getCoinIndices(
                poolAddress,
                h.path[i],
                h.path[i + 1]
            );
            (amountOut, ) = ICryptoPool(poolAddress).exchange(tokenIndexFrom, tokenIndexTo, amountIn, 0, new bytes(0));

            unchecked {
                i++;
            }
        }
    }

    function swapKokonutMeta(Hop memory h) internal returns (uint256 amountOut) {
        uint256 i;
        uint256 l = h.path.length;

        for (i = 0; i < l - 1; ) {
            uint256 amountIn = i == 0 ? h.amountIn : amountOut;
            address poolAddress = getPoolAddress(h.poolDataList[i]);
            h.path[i].approve(poolAddress, amountIn);
            (uint256 tokenIndexFrom, uint256 tokenIndexTo) = IRegistry(h.addr).getCoinIndices(
                poolAddress,
                h.path[i],
                h.path[i + 1]
            );
            (amountOut, ) = IMetaPool(poolAddress).exchangeUnderlying(tokenIndexFrom, tokenIndexTo, amountIn, 0);

            unchecked {
                i++;
            }
        }
    }
}

