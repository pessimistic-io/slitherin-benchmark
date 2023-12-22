// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ISwapRouter} from "./ISwapRouter.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

library LibAlgebra {
    using LibAsset for address;

    function getAlgebraPath(address[] memory path) private pure returns (bytes memory) {
        uint256 pl = path.length;
        bytes memory payload = new bytes(pl * 20);

        assembly {
            let i := 0
            let payloadPosition := add(payload, 32)
            let pathPosition := add(path, 32)

            for {

            } lt(i, pl) {
                i := add(i, 1)
                pathPosition := add(pathPosition, 32)
                payloadPosition := add(payloadPosition, 20)
            } {
                mstore(payloadPosition, shl(96, mload(pathPosition)))
            }
        }

        return payload;
    }

    function swapAlgebra(Hop memory h) internal returns (uint256 amountOut) {
        h.path[0].approve(h.addr, h.amountIn);
        if (h.path.length == 2) {
            amountOut = ISwapRouter(h.addr).exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: h.path[0],
                    tokenOut: h.path[1],
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: h.amountIn,
                    amountOutMinimum: 0,
                    limitSqrtPrice: 0
                })
            );
        } else {
            amountOut = ISwapRouter(h.addr).exactInput(
                ISwapRouter.ExactInputParams({
                    path: getAlgebraPath(h.path),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: h.amountIn,
                    amountOutMinimum: 0
                })
            );
        }
    }
}

