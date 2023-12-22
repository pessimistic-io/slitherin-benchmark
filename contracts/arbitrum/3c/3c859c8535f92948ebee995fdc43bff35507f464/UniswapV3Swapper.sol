// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {BytesLib} from "./BytesLib.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
import {IUniswapV3Callback} from "./IUniswapV3Callback.sol";
import {IErrors} from "./IErrors.sol";

/// @title UniswapV3Swapper
/// @notice A contract that swaps tokens on Uniswap V3
contract UniswapV3Swapper is IUniswapV3Callback {
    using SafeTransferLib for ERC20;
    using BytesLib for bytes;

    /// @notice The address of the Uniswap V3 factory on Arbitrum
    address public constant UNISWAP_V3_FACTORY =
        0x1F98431c8aD98523631AE4a59f267346ea31F984;

    /// @dev The minimum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MIN_TICK)
    uint160 internal constant _MIN_SQRT_RATIO = 4295128740;

    /// @dev The maximum value that can be returned from #getSqrtRatioAtTick. Equivalent to getSqrtRatioAtTick(MAX_TICK)
    uint160 internal constant _MAX_SQRT_RATIO =
        1461446703485210103287273052203988822378723970341;
    bytes32 internal constant _POOL_INIT_CODE_HASH =
        0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    /////////////////////////////////////////
    //        PUBLIC FUNCTIONS             //
    /////////////////////////////////////////
    /** @notice The callback implementation for UniswapV3 pools
        @param amount0Delta The amount of token0 received
        @param amount1Delta The amount of token1 received
        @param _data The encoded pool address, fee, and tokenOut address
    **/
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata _data
    ) external override {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported
        (address tokenIn, address tokenOut, uint24 fee) = decodePool(_data);

        if (msg.sender != getPool(tokenIn, tokenOut, fee))
            revert IErrors.InvalidCaller();

        SafeTransferLib.safeTransfer(
            ERC20(tokenIn),
            msg.sender,
            amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta)
        );
    }

    /////////////////////////////////////////
    //    INTERNAL & PRIVATE FUNCTIONS     //
    /////////////////////////////////////////
    /** @notice Decodes the payload and conducts the swaps
        @param fromAmount The amount of the fromToken being swapped
        @param toAmountMin The minimum amount of the toToken to receive
        @param path The path of the swap
        @param fee The fee of the swap
        @param receiver The address to receive the swapped tokens
        @return amountOut The amount of the toToken received
    **/
    function _swapOnUniswapV3(
        address[] memory path,
        uint24[] memory fee,
        uint256 fromAmount,
        uint256 toAmountMin,
        address receiver
    ) internal returns (uint256 amountOut) {
        if (path.length > 2) {
            amountOut = _executeSwap(
                path[0],
                path[1],
                fromAmount,
                fee[0],
                address(this)
            );
            for (uint256 i = 1; i < path.length - 2; ) {
                amountOut = _executeSwap(
                    path[i],
                    path[i + 1],
                    amountOut,
                    fee[i],
                    address(this)
                );
                unchecked {
                    i++;
                }
            }
            amountOut = _executeSwap(
                path[path.length - 2],
                path[path.length - 1],
                amountOut,
                fee[path.length - 2],
                receiver
            );
        } else {
            amountOut = _executeSwap(
                path[0],
                path[1],
                fromAmount,
                fee[0],
                receiver
            );
        }

        if (amountOut < toAmountMin) revert IErrors.InvalidMinOut(amountOut);
    }

    /** @notice Executes the swap with the simulated V3 pool from tokenIn, tokenOut, and fee
        @param tokenIn The address of the fromToken
        @param tokenOut The address of the toToken
        @param fromAmount The amount of fromToken to swap
        @param fee The fee for the pool
        @return The amount of toToken received
    **/
    function _executeSwap(
        address tokenIn,
        address tokenOut,
        uint256 fromAmount,
        uint24 fee,
        address receiver
    ) internal returns (uint256) {
        bool zeroForOne = tokenIn < tokenOut;

        if (zeroForOne) {
            (, int256 amountOut) = IUniswapV3Pool(
                getPool(tokenIn, tokenOut, fee)
            ).swap(
                    receiver,
                    zeroForOne,
                    int256(fromAmount),
                    _MIN_SQRT_RATIO,
                    abi.encodePacked(tokenIn, fee, tokenOut)
                );
            return uint256(-amountOut);
        } else {
            (int256 amountOut, ) = IUniswapV3Pool(
                getPool(tokenIn, tokenOut, fee)
            ).swap(
                    receiver,
                    zeroForOne,
                    int256(fromAmount),
                    _MAX_SQRT_RATIO,
                    abi.encodePacked(tokenIn, fee, tokenOut)
                );
            return uint256(-amountOut);
        }
    }

    /** @notice Simulates the address for the pool of two tokens
        @param tokenA The address of the first token
        @param tokenB The address of the second token
        @param fee The fee for the pool
        @return pool The address of the pool
    **/
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal pure returns (address pool) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            UNISWAP_V3_FACTORY,
                            keccak256(abi.encode(tokenA, tokenB, fee)),
                            _POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }

    /** @notice Decodes bytes to retrieve the fee and token addresses
        @param path The encoded data for fee and tokens
        @return tokenA tokenB fee
    **/
    function decodePool(
        bytes memory path
    ) internal pure returns (address tokenA, address tokenB, uint24 fee) {
        tokenA = path.toAddress(0);
        fee = path.toUint24(20);
        tokenB = path.toAddress(23);
    }
}

