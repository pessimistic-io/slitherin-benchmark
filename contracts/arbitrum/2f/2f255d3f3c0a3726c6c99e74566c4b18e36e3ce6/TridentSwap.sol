// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.11;

import "./ITridentRouter.sol";
import "./IPool.sol";
import "./IBentoBoxMinimal.sol";
import "./ERC20_IERC20.sol";

contract TridentSwap is ITridentRouter {
    // Custom Error

    error TooLittleReceived();

    function _exactInput(
        IBentoBoxMinimal bento,
        ExactInputParams memory params,
        address from
    ) internal returns (uint256 amountOut) {
        if (params.amountIn == 0) {
            // Pay the first pool directly.
            params.amountIn = IERC20(params.tokenIn).balanceOf(address(this));

            bento.transfer(
                params.tokenIn,
                from,
                params.path[0].pool,
                params.amountIn
            );
        }

        // Call every pool in the path.
        // Pool `N` should transfer its output tokens to pool `N+1` directly.
        // The last pool should transfer its output tokens to the user.
        // If the user wants to unwrap `wETH`, the final destination should be this contract and
        // a batch call should be made to `unwrapWETH`.
        uint256 n = params.path.length;
        for (uint256 i = 0; i < n; i = _increment(i)) {
            amountOut = IPool(params.path[i].pool).swap(params.path[i].data);
        }
        // Ensure that the slippage wasn't too much. This assumes that the pool is honest.
        if (amountOut < params.amountOutMinimum) revert TooLittleReceived();
    }

    function _increment(uint256 i) internal pure returns (uint256) {
        unchecked {
            return i + 1;
        }
    }
}

