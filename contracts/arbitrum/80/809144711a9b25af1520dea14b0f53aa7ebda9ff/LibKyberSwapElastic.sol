// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {IElasticRouter} from "./IElasticRouter.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

error KyberInvalidLengthsOfArrays();

library LibKyberSwapElastic {
    using LibAsset for address;

    function getPoolData(bytes memory poolData) private pure returns (bytes32 poolDataBytes32) {
        assembly {
            poolDataBytes32 := mload(add(poolData, 32))
        }
    }

    function convertPoolDataList(bytes[] memory poolDataList)
        private
        pure
        returns (bytes32[] memory poolDataListBytes32)
    {
        uint256 l = poolDataList.length;
        poolDataListBytes32 = new bytes32[](l);
        for (uint256 i = 0; i < l; ) {
            poolDataListBytes32[i] = getPoolData(poolDataList[i]);
            unchecked {
                i++;
            }
        }
    }

    function getKyberPath(address[] memory path, bytes32[] memory poolDataList) private pure returns (bytes memory) {
        bytes memory payload;
        uint256 pl = path.length;
        uint256 pdl = poolDataList.length;

        if (pl - 1 != pdl) {
            revert KyberInvalidLengthsOfArrays();
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

    function swapKyberElastic(Hop memory h) internal {
        h.path[0].approve(h.addr, h.amountIn);
        if (h.path.length == 2) {
            bytes memory poolData = h.poolDataList[0];
            uint24 fee;

            assembly {
                fee := shr(232, mload(add(poolData, 32)))
            }

            IElasticRouter(h.addr).swapExactInputSingle(
                IElasticRouter.ExactInputSingleParams({
                    tokenIn: h.path[0],
                    tokenOut: h.path[1],
                    fee: fee,
                    recipient: h.recipient,
                    deadline: block.timestamp,
                    amountIn: h.amountIn,
                    minAmountOut: 0,
                    limitSqrtP: 0
                })
            );
        } else {
            IElasticRouter(h.addr).swapExactInput(
                IElasticRouter.ExactInputParams({
                    path: getKyberPath(h.path, convertPoolDataList(h.poolDataList)),
                    recipient: h.recipient,
                    deadline: block.timestamp,
                    amountIn: h.amountIn,
                    minAmountOut: 0
                })
            );
        }
    }
}

