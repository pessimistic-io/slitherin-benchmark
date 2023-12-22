// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.8.9;
pragma abicoder v2;

import "./SafeCast.sol";
import "./IGrid.sol";
import "./IGridSwapCallback.sol";
import "./CallbackValidator.sol";
import "./GridAddress.sol";
import "./BoundaryMath.sol";
import "./AbstractPayments.sol";
import "./UniswapRouteQuoter.sol";
import "./IQuoter.sol";
import "./IUniswapV3PoolMinimum.sol";
import "./SwapPath.sol";
import "./Protocols.sol";
import "./GridBoundariesCounter.sol";
import "./CurveRouteQuoter.sol";

/// @title Provides quotes for swaps
/// @notice Allows users to compute the expected input or output without executing the swap
contract Quoter is IQuoter, IGridSwapCallback, AbstractPayments, UniswapRouteQuoter, CurveRouteQuoter {
    using SwapPath for bytes;
    using SafeCast for uint256;

    /// @dev The transient storage variable that checks a safety condition in ExactOutput swaps.
    uint256 private amountOutCached;

    constructor(
        address _gridexGridFactory,
        address _uniswapV3PoolFactory,
        address _uniswapV2PoolFactory,
        address _weth9
    ) AbstractPayments(_gridexGridFactory, _weth9) UniswapRouteQuoter(_uniswapV2PoolFactory, _uniswapV3PoolFactory) {}

    function getGrid(address tokenA, address tokenB, int24 resolution) private view returns (IGrid) {
        return IGrid(GridAddress.computeAddress(gridFactory, GridAddress.gridKey(tokenA, tokenB, resolution)));
    }

    /// @inheritdoc IGridSwapCallback
    function gridexSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes memory path) external view override {
        // swaps which are entirely contained within zero liquidity regions are not supported
        // Q_IAD: invalid amount delta
        require(amount0Delta > 0 || amount1Delta > 0, "Q_IAD");
        (address tokenIn, address tokenOut, int24 resolution) = path.decodeFirstGrid();
        CallbackValidator.validate(gridFactory, GridAddress.gridKey(tokenIn, tokenOut, resolution));

        (bool isExactInput, uint256 amountToPay, uint256 amountReceived) = amount0Delta > 0
            ? (tokenIn < tokenOut, uint256(amount0Delta), uint256(-amount1Delta))
            : (tokenOut < tokenIn, uint256(amount1Delta), uint256(-amount0Delta));

        IGrid grid = getGrid(tokenIn, tokenOut, resolution);
        (uint160 priceX96After, int24 boundaryAfter, , ) = grid.slot0();
        int24 boundaryLowerAfter = BoundaryMath.getBoundaryLowerAtBoundary(boundaryAfter, grid.resolution());

        // ensure that the full output amount has been received if the cache has been filled.
        if (!isExactInput && amountOutCached != 0) require(amountReceived == amountOutCached);

        assembly {
            let freePointerPtr := mload(0x40)
            mstore(freePointerPtr, amountToPay)
            mstore(add(freePointerPtr, 0x20), amountReceived)
            mstore(add(freePointerPtr, 0x40), priceX96After)
            mstore(add(freePointerPtr, 0x60), boundaryAfter)
            mstore(add(freePointerPtr, 0x80), boundaryLowerAfter)
            revert(freePointerPtr, 160)
        }
    }

    /// @dev Parses through a revert reason that should in principle carry the numeric quote
    function parseRevertReason(
        bytes memory reason
    )
        private
        pure
        returns (
            uint256 amountToPay,
            uint256 amountReceived,
            uint160 priceX96After,
            int24 boundaryAfter,
            int24 boundaryLowerAfter
        )
    {
        if (reason.length != 160) {
            if (reason.length < 68) revert("Unexpected error");
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }
        return abi.decode(reason, (uint256, uint256, uint160, int24, int24));
    }

    function handleRevert(
        bytes memory reason,
        IGrid grid,
        bool zeroForOne
    )
        private
        view
        returns (
            uint256 amountToPay,
            uint256 amountReceived,
            uint160 priceX96After,
            uint32 initializedBoundariesCrossed
        )
    {
        uint160 priceX96Before;
        int24 boundaryBefore;
        int24 boundaryLowerBefore;
        int24 boundaryAfter;
        int24 boundaryLowerAfter;
        (priceX96Before, boundaryBefore, , ) = grid.slot0();
        boundaryLowerBefore = BoundaryMath.getBoundaryLowerAtBoundary(boundaryBefore, grid.resolution());
        (amountToPay, amountReceived, priceX96After, boundaryAfter, boundaryLowerAfter) = parseRevertReason(reason);
        initializedBoundariesCrossed = GridBoundariesCounter.countInitializedBoundariesCrossed(
            GridBoundariesCounter.CountInitializedBoundariesCrossedParameters({
                grid: grid,
                zeroForOne: zeroForOne,
                priceX96Before: priceX96Before,
                boundaryBefore: boundaryBefore,
                boundaryLowerBefore: boundaryLowerBefore,
                priceX96After: priceX96After,
                boundaryAfter: boundaryAfter,
                boundaryLowerAfter: boundaryLowerAfter
            })
        );
    }

    /// @inheritdoc IQuoter
    function quoteExactInputSingle(
        QuoteExactInputSingleParameters memory parameters
    ) public override returns (QuoteExactResult memory result) {
        return quoteExactInputSingleWithAmountIn(parameters);
    }

    /// @inheritdoc IQuoter
    function quoteExactInputSingleWithAmountIn(
        QuoteExactInputSingleParameters memory parameters
    ) public returns (QuoteExactResult memory result) {
        bool zeroForOne = parameters.tokenIn < parameters.tokenOut;

        uint256 gasBefore = gasleft();
        try
            getGrid(parameters.tokenIn, parameters.tokenOut, parameters.resolution).swap(
                address(this),
                zeroForOne,
                parameters.amountIn.toInt256(),
                parameters.priceLimit == 0
                    ? (zeroForOne ? BoundaryMath.MIN_RATIO : BoundaryMath.MAX_RATIO)
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
            ) = handleRevert(
                reason,
                getGrid(parameters.tokenIn, parameters.tokenOut, parameters.resolution),
                zeroForOne
            );
        }
    }

    /// @inheritdoc IQuoter
    function quoteExactOutputSingle(
        QuoteExactOutputSingleParameters memory parameters
    ) public override returns (QuoteExactResult memory result) {
        bool zeroForOne = parameters.tokenIn < parameters.tokenOut;
        IGrid grid = getGrid(parameters.tokenIn, parameters.tokenOut, parameters.resolution);

        // the output amount is cached for verification in the swap callback if PriceLimit is not specified
        if (parameters.priceLimit == 0) amountOutCached = parameters.amountOut;
        uint256 gasBefore = gasleft();
        try
            grid.swap(
                address(this),
                zeroForOne,
                -parameters.amountOut.toInt256(),
                parameters.priceLimit == 0
                    ? (zeroForOne ? BoundaryMath.MIN_RATIO : BoundaryMath.MAX_RATIO)
                    : parameters.priceLimit,
                abi.encodePacked(parameters.tokenOut, uint8(0), parameters.resolution, parameters.tokenIn)
            )
        {} catch (bytes memory reason) {
            result.gasEstimate = gasBefore - gasleft();
            // clear cache
            if (parameters.priceLimit == 0) delete amountOutCached;

            (
                result.amountToPay,
                result.amountOut,
                result.priceAfter,
                result.initializedBoundariesCrossed
            ) = handleRevert(reason, grid, zeroForOne);
        }
    }

    function resolveExactIn(
        uint8 protocol,
        bytes memory path,
        uint256 amountIn
    ) private returns (QuoteExactResult memory result) {
        (address tokenIn, address tokenOut, int24 resolution) = path.decodeFirstGrid();
        if (protocol == Protocols.GRIDEX) {
            result = quoteExactInputSingle(
                QuoteExactInputSingleParameters({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    resolution: resolution,
                    priceLimit: 0
                })
            );
        } else if (protocol == Protocols.UNISWAPV3) {
            result = v3QuoteExactInputSingle(
                QuoteExactInputSingleParameters({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: amountIn,
                    resolution: resolution,
                    priceLimit: 0
                })
            );
        } else if (protocol == Protocols.UNISWAPV2) {
            result.amountToPay = amountIn;
            result.amountOut = v2GetPairAmountOut(
                V2GetPairAmountOutParameters({amountIn: amountIn, tokenIn: tokenIn, tokenOut: tokenOut})
            );
            result.gasEstimate = 50000;
        }
    }

    /// @inheritdoc IQuoter
    function quoteExactInput(
        bytes memory path,
        uint256 amountIn
    )
        public
        override
        returns (
            uint256 amountOut,
            uint256[] memory amountInList,
            uint160[] memory priceAfterList,
            uint32[] memory initializedBoundariesCrossedList,
            uint256 gasEstimate
        )
    {
        priceAfterList = new uint160[](numGrids(path));
        initializedBoundariesCrossedList = new uint32[](priceAfterList.length);
        amountInList = new uint256[](priceAfterList.length);
        uint256 i = 0;
        QuoteExactResult memory _result;
        while (true) {
            uint8 protocol = path.getProtocol();
            if (protocol < Protocols.CURVE) _result = resolveExactIn(protocol, path, amountIn);
            else {
                (, , address poolAddress, address swapAddress, uint8 tokenInIndex, uint8 tokenOutIndex) = path
                    .decodeFirstCurvePool();
                CurveQuoteExactInputSingleParameters memory params = CurveQuoteExactInputSingleParameters({
                    protocol: protocol,
                    poolAddress: poolAddress,
                    tokenInIndex: tokenInIndex,
                    tokenOutIndex: tokenOutIndex,
                    amountIn: amountIn,
                    swapAddress: swapAddress
                });
                if (protocol == Protocols.CURVE5 || protocol == Protocols.CURVE6)
                    _result = Curve56QuoteExactInputSingle(params);
                else _result = CurveQuoteExactInputSingle(params);
            }
            priceAfterList[i] = _result.priceAfter;
            initializedBoundariesCrossedList[i] = _result.initializedBoundariesCrossed;
            amountInList[i] = _result.amountToPay;
            amountIn = _result.amountOut;
            unchecked {
                gasEstimate += _result.gasEstimate;
                i++;
            }
            /// decide whether to continue or terminate
            if (path.hasMultipleGrids()) path = path.skipToken();
            else return (amountIn, amountInList, priceAfterList, initializedBoundariesCrossedList, gasEstimate);
        }
    }

    function resolveExactOut(
        uint8 protocol,
        address tokenIn,
        address tokenOut,
        int24 resolution,
        uint256 amountOut
    ) private returns (QuoteExactResult memory result) {
        if (protocol == Protocols.GRIDEX) {
            result = quoteExactOutputSingle(
                QuoteExactOutputSingleParameters({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountOut: amountOut,
                    resolution: resolution,
                    priceLimit: 0
                })
            );
        } else if (protocol == Protocols.UNISWAPV3) {
            result = v3QuoteExactOutputSingle(
                QuoteExactOutputSingleParameters({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountOut: amountOut,
                    resolution: resolution,
                    priceLimit: 0
                })
            );
        } else if (protocol == Protocols.UNISWAPV2) {
            result.amountOut = amountOut;
            result.amountToPay = v2GetPairAmountIn(
                V2GetPairAmountInParameters({amountOut: amountOut, tokenIn: tokenIn, tokenOut: tokenOut})
            );
            result.gasEstimate = 50000;
        }
    }

    /// @inheritdoc IQuoter
    function quoteExactOutput(
        bytes memory path,
        uint256 amountOut
    )
        public
        override
        returns (
            uint256 amountIn,
            uint256[] memory amountOutList,
            uint160[] memory priceAfterList,
            uint32[] memory initializedBoundariesCrossedList,
            uint256 gasEstimate
        )
    {
        priceAfterList = new uint160[](numGrids(path));
        initializedBoundariesCrossedList = new uint32[](priceAfterList.length);
        amountOutList = new uint256[](priceAfterList.length);
        uint256 i = 0;
        QuoteExactResult memory _result;
        while (true) {
            (address tokenOut, address tokenIn, int24 resolution) = path.decodeFirstGrid();
            _result = resolveExactOut(path.getProtocol(), tokenIn, tokenOut, resolution, amountOut);
            priceAfterList[i] = _result.priceAfter;
            initializedBoundariesCrossedList[i] = _result.initializedBoundariesCrossed;
            amountOutList[i] = _result.amountOut;
            amountOut = _result.amountToPay;
            unchecked {
                gasEstimate += _result.gasEstimate;
                i++;
            }
            // decide whether to continue or terminate
            if (path.hasMultipleGrids()) path = path.skipToken();
            else return (amountOut, amountOutList, priceAfterList, initializedBoundariesCrossedList, gasEstimate);
        }
    }

    function numGrids(bytes memory path) internal pure returns (uint256) {
        bytes memory pathCopy = path;
        uint256 l = 1;
        while (pathCopy.hasMultipleGrids()) {
            unchecked {
                l++;
            }
            pathCopy = pathCopy.skipToken();
        }
        return l;
    }
}

