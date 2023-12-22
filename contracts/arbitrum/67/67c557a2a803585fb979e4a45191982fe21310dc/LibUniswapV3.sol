// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IUniswapV3RouterV1} from "./IUniswapV3RouterV1.sol";
import {IUniswapV3RouterV2} from "./IUniswapV3RouterV2.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

error UniswapV3InvalidLengthsOfArrays();

library LibUniswapV3 {
    using LibAsset for address;

    function getPoolData(bytes memory poolData) private pure returns (bytes32 poolDataBytes32) {
        assembly {
            poolDataBytes32 := mload(add(poolData, 32))
        }
    }

    function convertPoolDataList(
        bytes[] memory poolDataList
    ) private pure returns (bytes32[] memory poolDataListBytes32) {
        uint256 l = poolDataList.length;
        poolDataListBytes32 = new bytes32[](l);
        for (uint256 i = 0; i < l; ) {
            poolDataListBytes32[i] = getPoolData(poolDataList[i]);
            unchecked {
                i++;
            }
        }
    }

    function getUniswapV3Path(
        address[] memory path,
        bytes32[] memory poolDataList
    ) private pure returns (bytes memory) {
        bytes memory payload;
        uint256 pl = path.length;
        uint256 pdl = poolDataList.length;

        if (pl - 1 != pdl) {
            revert UniswapV3InvalidLengthsOfArrays();
        }

        assembly {
            payload := mload(0x40)
            let i := 0
            let payloadPosition := add(payload, 32)
            let pathPosition := add(path, 32)
            let poolDataPosition := add(poolDataList, 32)

            for {

            } lt(i, pl) {
                i := add(i, 1)
                pathPosition := add(pathPosition, 32)
            } {
                mstore(payloadPosition, shl(96, mload(pathPosition)))
                payloadPosition := add(payloadPosition, 20)

                if lt(i, pdl) {
                    mstore(payloadPosition, mload(poolDataPosition))
                    payloadPosition := add(payloadPosition, 3)
                    poolDataPosition := add(poolDataPosition, 32)
                }
            }

            mstore(payload, sub(sub(payloadPosition, payload), 32))
            mstore(0x40, and(add(payloadPosition, 31), not(31)))
        }

        return payload;
    }

    function swapUniswapV3V1(Hop memory h) internal returns (uint256 amountOut) {
        h.path[0].approve(h.addr, h.amountIn);
        if (h.path.length == 2) {
            bytes memory poolData = h.poolDataList[0];
            uint24 fee;

            assembly {
                fee := shr(232, mload(add(poolData, 32)))
            }

            amountOut = IUniswapV3RouterV1(h.addr).exactInputSingle(
                IUniswapV3RouterV1.ExactInputSingleParams({
                    tokenIn: h.path[0],
                    tokenOut: h.path[1],
                    fee: fee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: h.amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        } else {
            amountOut = IUniswapV3RouterV1(h.addr).exactInput(
                IUniswapV3RouterV1.ExactInputParams({
                    path: getUniswapV3Path(h.path, convertPoolDataList(h.poolDataList)),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: h.amountIn,
                    amountOutMinimum: 0
                })
            );
        }
    }

    function swapUniswapV3V2(Hop memory h) internal returns (uint256 amountOut) {
        h.path[0].approve(h.addr, h.amountIn);
        if (h.path.length == 2) {
            bytes memory poolData = h.poolDataList[0];
            uint24 fee;

            assembly {
                fee := shr(232, mload(add(poolData, 32)))
            }

            amountOut = IUniswapV3RouterV2(h.addr).exactInputSingle(
                IUniswapV3RouterV2.ExactInputSingleParams({
                    tokenIn: h.path[0],
                    tokenOut: h.path[1],
                    fee: fee,
                    recipient: address(this),
                    amountIn: h.amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        } else {
            amountOut = IUniswapV3RouterV2(h.addr).exactInput(
                IUniswapV3RouterV2.ExactInputParams({
                    path: getUniswapV3Path(h.path, convertPoolDataList(h.poolDataList)),
                    recipient: address(this),
                    amountIn: h.amountIn,
                    amountOutMinimum: 0
                })
            );
        }
    }
}

