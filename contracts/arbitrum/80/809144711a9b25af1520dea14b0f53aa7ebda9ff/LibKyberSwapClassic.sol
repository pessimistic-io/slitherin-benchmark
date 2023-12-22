// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import "./IERC20.sol";
import {IDMMExchangeRouter} from "./IDMMExchangeRouter.sol";
import {LibAsset} from "./LibAsset.sol";
import {Hop, LibHop} from "./LibHop.sol";

library LibKyberSwapClassic {
    using LibAsset for address;
    using LibHop for Hop;

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

    function swapKyberClassic(Hop memory h) internal {
        h.enforceSingleHop();
        h.path[0].approve(h.addr, h.amountIn);

        IDMMExchangeRouter(h.addr).swapExactTokensForTokens(
            h.amountIn,
            0,
            h.path,
            getTokens(h.path),
            h.recipient,
            block.timestamp
        );
    }
}

