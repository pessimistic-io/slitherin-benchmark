// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IAsset} from "./IAsset.sol";
import {IVault} from "./IVault.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

library LibBalancerV2 {
    using LibAsset for address;

    function getPoolId(bytes memory poolData) private pure returns (bytes32 poolId) {
        assembly {
            poolId := mload(add(poolData, 32))
        }
    }

    function swapBalancerV2(Hop memory h) internal returns (uint256 amountOut) {
        h.path[0].approve(h.addr, h.amountIn);
        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: address(this),
            fromInternalBalance: false,
            recipient: payable(address(this)),
            toInternalBalance: false
        });
        if (h.path.length == 2) {
            amountOut = IVault(h.addr).swap(
                IVault.SingleSwap({
                    poolId: getPoolId(h.poolDataList[0]),
                    kind: IVault.SwapKind.GIVEN_IN,
                    assetIn: IAsset(h.path[0]),
                    assetOut: IAsset(h.path[1]),
                    amount: h.amountIn,
                    userData: "0x"
                }),
                funds,
                0,
                block.timestamp
            );
        } else {
            uint256 i;
            uint256 l = h.path.length;
            IVault.BatchSwapStep[] memory swaps = new IVault.BatchSwapStep[](h.path.length - 1);
            IAsset[] memory balancerAssets = new IAsset[](h.path.length);
            int256[] memory limits = new int256[](h.path.length);

            for (i = 0; i < l - 1; ) {
                swaps[i] = IVault.BatchSwapStep({
                    poolId: getPoolId(h.poolDataList[i]),
                    assetInIndex: i,
                    assetOutIndex: i + 1,
                    amount: i == 0 ? h.amountIn : 0,
                    userData: "0x"
                });
                balancerAssets[i] = IAsset(h.path[i]);
                limits[i] = i == 0 ? int256(h.amountIn) : int256(0);

                if (i == h.path.length - 2) {
                    balancerAssets[i + 1] = IAsset(h.path[i + 1]);
                    limits[i + 1] = 0;
                }

                unchecked {
                    i++;
                }
            }

            int256[] memory deltas = IVault(h.addr).batchSwap(
                IVault.SwapKind.GIVEN_IN,
                swaps,
                balancerAssets,
                funds,
                limits,
                block.timestamp
            );

            int256 delta = deltas[l - 1];
            amountOut = uint256(delta < 0 ? -delta : delta);
        }
    }
}

