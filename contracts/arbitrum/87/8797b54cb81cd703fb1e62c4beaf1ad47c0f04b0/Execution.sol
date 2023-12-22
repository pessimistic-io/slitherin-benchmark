// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {SharedLiquidity} from "./SharedLiquidity.sol";

abstract contract Execution is SharedLiquidity {
    error EnterFailed();
    error ExitFailed();

    function _enter() internal returns (uint256 sharesFromEnter) {
        uint256 liquidityBefore = totalLiquidity();
        _enterLogic();
        uint256 liquidityAfter = totalLiquidity();
        if (liquidityBefore >= liquidityAfter) {
            revert EnterFailed();
        }

        uint256 shares = _sharesFromLiquidityDelta(
            liquidityBefore,
            liquidityAfter
        );
        _issueShares(shares);
        return shares;
    }

    function _exit(uint256 shares) internal {
        uint256 liquidity = _toLiquidity(shares);
        _withdrawShares(shares);
        _exitLogic(liquidity);
    }

    function _enterLogic() internal virtual;

    function _exitLogic(uint256 liquidity) internal virtual;
}

