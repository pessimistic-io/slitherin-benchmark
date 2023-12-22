// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20.sol";
import {ILBRouter} from "./ILBRouter.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop} from "./LibHop.sol";

library LibTraderJoeV2_1 {
    using LibAsset for address;

    function getPairBinStep(bytes memory poolData) private pure returns (uint256 pairBinStep) {
        assembly {
            pairBinStep := mload(add(poolData, 32))
        }
    }

    function getPairBinSteps(bytes[] memory poolDataList) private pure returns (uint256[] memory pairBinSteps) {
        uint256 pdl = poolDataList.length;
        pairBinSteps = new uint256[](pdl);

        for (uint256 i = 0; i < pdl; ) {
            pairBinSteps[i] = getPairBinStep(poolDataList[i]);
            unchecked {
                i++;
            }
        }
    }

    function getTokens(address[] memory path) private pure returns (IERC20[] memory tokens) {
        uint256 l = path.length;
        tokens = new IERC20[](l);
        for (uint256 i = 0; i < l; ) {
            tokens[i] = IERC20(path[i]);
            unchecked {
                i++;
            }
        }
    }

    function getVersions(address[] memory path) private pure returns (ILBRouter.Version[] memory versions) {
        uint256 l = path.length - 1;
        versions = new ILBRouter.Version[](l);
        for (uint256 i = 0; i < l; ) {
            versions[i] = ILBRouter.Version.V2_1;
            unchecked {
                i++;
            }
        }
    }

    function swapTraderJoeV2_1(Hop memory h) internal returns (uint256 amountOut) {
        h.path[0].approve(h.addr, h.amountIn);
        amountOut = ILBRouter(h.addr).swapExactTokensForTokens(
            h.amountIn,
            0,
            ILBRouter.Path({
                pairBinSteps: getPairBinSteps(h.poolDataList),
                versions: getVersions(h.path),
                tokenPath: getTokens(h.path)
            }),
            h.recipient,
            block.timestamp
        );
    }
}

