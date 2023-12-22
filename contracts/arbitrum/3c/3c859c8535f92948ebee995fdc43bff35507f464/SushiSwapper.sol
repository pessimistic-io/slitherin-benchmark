// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {IErrors} from "./IErrors.sol";

/// @title UniswapV2 Swapper
/// @notice Tokens can be swapped on UniswapV2 and deposited into Y2K vaults
library SushiSwapper {
    using SafeTransferLib for ERC20;

    /////////////////////////////////////////
    //        PUBLIC FUNCTIONS             //
    /////////////////////////////////////////
    function _swapOnSushi(
        address[] memory path,
        uint256 fromAmount,
        uint256 toAmountMin,
        address receiver
    ) internal returns (uint256 amountOut) {
        uint256[] memory amounts = new uint256[](path.length - 1);
        address[] memory pairs = new address[](path.length - 1);

        // NOTE: Use amountOut to reduce declaration of additional variable
        amountOut = fromAmount;
        for (uint256 i = 0; i < path.length - 1; ) {
            {
                address fromToken = path[i];
                address toToken = path[i + 1];

                pairs[i] = _getPair(fromToken, toToken);
                (uint256 reserveA, uint256 reserveB, ) = IUniswapV2Pair(
                    pairs[i]
                ).getReserves();

                if (fromToken > toToken)
                    (reserveA, reserveB) = (reserveB, reserveA);

                amounts[i] =
                    ((amountOut * 997) * reserveB) /
                    ((reserveA * 1000) + (amountOut * 997));
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
                            0xc35DADB65012eC5796536bD9864eD8773aBc74C4,
                            keccak256(abi.encodePacked(tokenA, tokenB)),
                            hex"e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303" // init code hash
                        )
                    )
                )
            )
        );
    }

    /** @notice Executes swaps on UniswapV2 fork
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
            IUniswapV2Pair(pairs[0]).swap(
                zeroForOne ? 0 : amounts[0],
                zeroForOne ? amounts[0] : 0,
                pairs[1],
                ""
            );
            for (uint256 i = 1; i < pairs.length - 1; ) {
                zeroForOne = path[i] < path[i + 1];
                IUniswapV2Pair(pairs[i]).swap(
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
            IUniswapV2Pair(pairs[pairs.length - 1]).swap(
                zeroForOne ? 0 : amounts[pairs.length - 1],
                zeroForOne ? amounts[pairs.length - 1] : 0,
                receiver,
                ""
            );
        } else {
            IUniswapV2Pair(pairs[0]).swap(
                zeroForOne ? 0 : amounts[0],
                zeroForOne ? amounts[0] : 0,
                receiver,
                ""
            );
        }

        return amounts[amounts.length - 1];
    }
}

