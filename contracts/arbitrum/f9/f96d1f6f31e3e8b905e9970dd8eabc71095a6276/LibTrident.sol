// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {ITridentRouter} from "./ITridentRouter.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

error TridentInvalidLengthsOfArrays();

library LibTrident {
    using LibAsset for address;

    function getPoolAddress(bytes memory poolData) private pure returns (address poolAddress) {
        assembly {
            poolAddress := shr(96, mload(add(poolData, 32)))
        }
    }

    function getTridentPath(
        address[] memory path,
        bytes[] memory poolDataList,
        address recipient
    ) private pure returns (ITridentRouter.Path[] memory tridentPath) {
        uint256 pl = path.length;
        uint256 pdl = poolDataList.length;

        if (pl - 1 != pdl) {
            revert TridentInvalidLengthsOfArrays();
        }

        tridentPath = new ITridentRouter.Path[](pl);

        for (uint256 i = 0; i < pdl; ) {
            tridentPath[i].pool = getPoolAddress(poolDataList[i]);
            tridentPath[i].data = encodeTridentData(path[i], i == pdl - 1 ? recipient : tridentPath[i].pool, false);

            unchecked {
                i++;
            }
        }
    }

    function encodeTridentData(
        address tokenIn,
        address recipient,
        bool unwrapBento
    ) private pure returns (bytes memory data) {
        data = new bytes(41);
        assembly {
            mstore(add(data, 32), shl(96, tokenIn))
            mstore(add(data, 52), shl(96, recipient))
            mstore(add(data, 72), shl(248, unwrapBento))
        }
        return data;
    }

    function swapTrident(Hop memory h) internal {
        h.path[0].approve(h.addr, h.amountIn);
        if (h.path.length == 2) {
            ITridentRouter(h.addr).exactInputSingle(
                ITridentRouter.ExactInputSingleParams({
                    amountIn: h.amountIn,
                    amountOutMinimum: 0,
                    pool: getPoolAddress(h.poolDataList[0]),
                    tokenIn: h.path[0],
                    data: encodeTridentData(h.path[0], h.recipient, false)
                })
            );
        } else {
            ITridentRouter(h.addr).exactInput(
                ITridentRouter.ExactInputParams({
                    tokenIn: h.path[0],
                    amountIn: h.amountIn,
                    amountOutMinimum: 0,
                    path: getTridentPath(h.path, h.poolDataList, h.recipient)
                })
            );
        }
    }
}

