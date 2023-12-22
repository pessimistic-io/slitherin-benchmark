// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {ICamelotPair} from "./ICamelotPair.sol";
import {IErrors} from "./IErrors.sol";

/// @title Camelot Swapper
/// @notice Tokens can be swapped on Camelot and deposited into Y2K vaults
library CamelotSwapper {
    using SafeTransferLib for ERC20;

    /////////////////////////////////////////
    //        PUBLIC FUNCTIONS             //
    /////////////////////////////////////////
    /** @notice Calculates the amounts to be received, pairs addresses, and swaps with each pair
        @param path The array of token addresses to swap between
        @param fromAmount The amount of fromToken to swap
        @param toAmountMin The minimum amount of destination token to receive
        @return amountOut The amount of destination token being received
    **/
    function _swapOnCamelot(
        address[] memory path,
        uint256 fromAmount,
        uint256 toAmountMin,
        address receiver
    ) internal returns (uint256 amountOut) {
        uint256[] memory amounts = new uint256[](path.length - 1);
        address[] memory pairs = new address[](path.length - 1);

        amountOut = fromAmount;
        for (uint256 i = 0; i < path.length - 1; ) {
            {
                address fromToken = path[i];
                address toToken = path[i + 1];

                pairs[i] = _getPair(fromToken, toToken);
                (uint256 reserveA, uint256 reserveB, , ) = ICamelotPair(
                    pairs[i]
                ).getReserves();

                if (fromToken > toToken)
                    (reserveA, reserveB) = (reserveB, reserveA);

                // NOTE: Need to query the fee percent set by Camelot
                amounts[i] = ICamelotPair(pairs[i]).getAmountOut(
                    amountOut,
                    fromToken
                );
                amountOut = amounts[i];
            }

            unchecked {
                i++;
            }
        }

        if (amounts[amounts.length - 1] < toAmountMin)
            revert IErrors.InvalidMinOut(amounts[amounts.length - 1]);

        SafeTransferLib.safeTransfer(ERC20(path[0]), pairs[0], fromAmount);

        return _executeSwap(path, pairs, amounts, receiver);
    }

    /** @notice Simulates the address for the pair of two tokens
        @param tokenA The address of the first token
        @param tokenB The address of the second token
        @return pair The address of the pair
    **/
    function _getPair(
        address tokenA,
        address tokenB
    ) internal pure returns (address pair) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            0x6EcCab422D763aC031210895C81787E87B43A652,
                            keccak256(abi.encodePacked(tokenA, tokenB)),
                            hex"a856464ae65f7619087bc369daaf7e387dae1e5af69cfa7935850ebf754b04c1" // init code hash
                        )
                    )
                )
            )
        );
    }

    /** @notice Executes swaps on Camelot
        @param path The array of token addresses to swap between
        @param pairs The array of pairs to swap through
        @param amounts The array of amounts to swap with each pair 
        @return The amount of destination token being received
    **/
    function _executeSwap(
        address[] memory path,
        address[] memory pairs,
        uint256[] memory amounts,
        address receiver
    ) internal returns (uint256) {
        bool zeroForOne = path[0] < path[1];
        if (pairs.length > 1) {
            ICamelotPair(pairs[0]).swap(
                zeroForOne ? 0 : amounts[0],
                zeroForOne ? amounts[0] : 0,
                pairs[1],
                ""
            );
            for (uint256 i = 1; i < pairs.length - 1; ) {
                zeroForOne = path[i] < path[i + 1];
                ICamelotPair(pairs[i]).swap(
                    zeroForOne ? 0 : amounts[i],
                    zeroForOne ? amounts[i] : 0,
                    pairs[i + 1],
                    ""
                );
                unchecked {
                    i++;
                }
            }
            zeroForOne = path[path.length - 2] < path[path.length - 1];
            ICamelotPair(pairs[pairs.length - 1]).swap(
                zeroForOne ? 0 : amounts[pairs.length - 1],
                zeroForOne ? amounts[pairs.length - 1] : 0,
                receiver,
                ""
            );
        } else {
            ICamelotPair(pairs[0]).swap(
                zeroForOne ? 0 : amounts[0],
                zeroForOne ? amounts[0] : 0,
                receiver,
                ""
            );
        }

        return amounts[amounts.length - 1];
    }
}

