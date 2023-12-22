// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.9;
pragma abicoder v2;

import "./SafeCast.sol";
import "./IUniswapV3SwapCallback.sol";
import "./IUniswapV3PoolMinimum.sol";
import "./IUniswapRouteQuoter.sol";
import "./UniswapV3CallbackValidator.sol";
import "./UniswapV2Library.sol";
import "./UniswapV3PoolTicksCounter.sol";
import "./UniswapV3PoolAddress.sol";
import "./SwapPath.sol";
import "./Ratio.sol";

contract UniswapRouteQuoter is IUniswapRouteQuoter, IUniswapV3SwapCallback {
    using SwapPath for bytes;
    using SafeCast for uint256;
    using UniswapV3PoolTicksCounter for IUniswapV3PoolMinimum;

    uint256 private v3AmountOutCached;

    address private immutable v3PoolFactory;
    address private immutable v2PoolFactory;

    constructor(address _v2factory, address _v3factory) {
        v3PoolFactory = _v3factory;
        v2PoolFactory = _v2factory;
    }

    function getPool(address tokenA, address tokenB, uint24 resolution) private view returns (IUniswapV3PoolMinimum) {
        return
            IUniswapV3PoolMinimum(
                UniswapV3PoolAddress.computeAddress(
                    v3PoolFactory,
                    UniswapV3PoolAddress.poolKey(tokenA, tokenB, resolution)
                )
            );
    }

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes memory path) external view override {
        // swaps which are entirely contained within zero liquidity regions are not supported
        require(amount0Delta > 0 || amount1Delta > 0);
        (address tokenIn, address tokenOut, int24 tickSpacingTmp) = path.decodeFirstGrid();
        UniswapV3CallbackValidator.validate(v3PoolFactory, tokenIn, tokenOut, uint24(tickSpacingTmp));

        (bool isExactInput, uint256 amountToPay, uint256 amountReceived) = amount0Delta > 0
            ? (tokenIn < tokenOut, uint256(amount0Delta), uint256(-amount1Delta))
            : (tokenOut < tokenIn, uint256(amount1Delta), uint256(-amount0Delta));

        IUniswapV3PoolMinimum pool = getPool(tokenIn, tokenOut, uint24(tickSpacingTmp));
        (uint160 sqrtPriceX96After, int24 tickAfter, , , , , ) = pool.slot0();

        if (!isExactInput && v3AmountOutCached != 0) require(amountReceived == v3AmountOutCached);
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, amountToPay)
            mstore(add(ptr, 0x20), amountReceived)
            mstore(add(ptr, 0x40), sqrtPriceX96After)
            mstore(add(ptr, 0x60), tickAfter)
            revert(ptr, 128)
        }
    }

    function parseV3RevertReason(
        bytes memory reason
    ) private pure returns (uint256 amountToPay, uint256 amountReceived, uint160 sqrtPriceX96After, int24 tickAfter) {
        if (reason.length != 128) {
            if (reason.length < 68) revert("Unexpected error");
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }
        return abi.decode(reason, (uint256, uint256, uint160, int24));
    }

    function handleV3Revert(
        bytes memory reason,
        IUniswapV3PoolMinimum pool
    )
        private
        view
        returns (uint256 amountToPay, uint256 amountReceived, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed)
    {
        int24 tickBefore;
        int24 tickAfter;
        (, tickBefore, , , , , ) = pool.slot0();
        (amountToPay, amountReceived, sqrtPriceX96After, tickAfter) = parseV3RevertReason(reason);

        initializedTicksCrossed = pool.countInitializedTicksCrossed(tickBefore, tickAfter);

        return (amountToPay, amountReceived, sqrtPriceX96After, initializedTicksCrossed);
    }

    function v3QuoteExactInputSingle(
        QuoteExactInputSingleParameters memory parameters
    ) public override returns (QuoteExactResult memory result) {
        bool zeroForOne = parameters.tokenIn < parameters.tokenOut;
        IUniswapV3PoolMinimum pool = getPool(parameters.tokenIn, parameters.tokenOut, uint24(parameters.resolution));

        uint256 gasBefore = gasleft();
        unchecked {
            try
                pool.swap(
                    address(this),
                    zeroForOne,
                    parameters.amountIn.toInt256(),
                    parameters.priceLimit == 0
                        ? (zeroForOne ? Ratio.MIN_SQRT_RATIO_PLUS_ONE : Ratio.MAX_SQRT_RATIO_MINUS_ONE)
                        : parameters.priceLimit,
                    abi.encodePacked(parameters.tokenIn, uint8(0), parameters.resolution, parameters.tokenOut)
                )
            {} catch (bytes memory reason) {
                result.gasEstimate = gasBefore - gasleft();
                (
                    result.amountToPay,
                    result.amountOut,
                    result.priceAfter,
                    result.initializedBoundariesCrossed
                ) = handleV3Revert(reason, pool);
            }
        }
    }

    function v3QuoteExactOutputSingle(
        QuoteExactOutputSingleParameters memory parameters
    ) public override returns (QuoteExactResult memory result) {
        bool zeroForOne = parameters.tokenIn < parameters.tokenOut;
        IUniswapV3PoolMinimum pool = getPool(parameters.tokenIn, parameters.tokenOut, uint24(parameters.resolution));

        if (parameters.priceLimit == 0) v3AmountOutCached = parameters.amountOut;
        uint256 gasBefore = gasleft();
        try
            pool.swap(
                address(this),
                zeroForOne,
                -parameters.amountOut.toInt256(),
                parameters.priceLimit == 0
                    ? (zeroForOne ? Ratio.MIN_SQRT_RATIO_PLUS_ONE : Ratio.MAX_SQRT_RATIO_MINUS_ONE)
                    : parameters.priceLimit,
                abi.encodePacked(parameters.tokenOut, uint8(0), parameters.resolution, parameters.tokenIn)
            )
        {} catch (bytes memory reason) {
            result.gasEstimate = gasBefore - gasleft();
            if (parameters.priceLimit == 0) delete v3AmountOutCached;
            (
                result.amountToPay,
                result.amountOut,
                result.priceAfter,
                result.initializedBoundariesCrossed
            ) = handleV3Revert(reason, pool);
        }
    }

    function v2GetPairAmountOut(V2GetPairAmountOutParameters memory parameters) public view override returns (uint256) {
        (uint256 reserveIn, uint256 reserveOut) = UniswapV2Library.getReserves(
            v2PoolFactory,
            parameters.tokenIn,
            parameters.tokenOut
        );
        return UniswapV2Library.getAmountOut(parameters.amountIn, reserveIn, reserveOut);
    }

    function v2GetPairAmountIn(V2GetPairAmountInParameters memory parameters) public view override returns (uint256) {
        (uint256 reserveIn, uint256 reserveOut) = UniswapV2Library.getReserves(
            v2PoolFactory,
            parameters.tokenIn,
            parameters.tokenOut
        );
        return UniswapV2Library.getAmountIn(parameters.amountOut, reserveIn, reserveOut);
    }
}

