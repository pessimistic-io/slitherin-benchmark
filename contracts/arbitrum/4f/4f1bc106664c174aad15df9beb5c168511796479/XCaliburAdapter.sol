//SPDX-License-Identifier: ISC

pragma solidity ^0.8.13;

import "./IRouter.sol";
import "./ISwapFactory.sol";
import "./IWETH.sol";
import "./IERC20.sol";
import "./Math.sol";
import "./ISwapPair.sol";
import {SafeERC20} from "./SafeERC20.sol";

abstract contract XCaliburAdapter is IRouter {
    using SafeERC20 for IERC20;

    struct XcaliburParams {
        uint256 amountIn;
        uint256 amountOutMin;
        route[] routes;
        uint256 deadline;
    }

    struct route {
        address from;
        address to;
        bool stable;
    }

    address public immutable xcalFactory;
    IWETH public immutable xcalWeth;
    uint256 internal constant MINIMUM_LIQUIDITY = 10 ** 3;
    bytes32 immutable xcalPairCodeHash;
    address internal constant xcalRouter = address(0x8e72bf5A45F800E182362bDF906DFB13d5D5cb5d);

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "BaseV1Router: EXPIRED");
        _;
    }

    constructor(address _factory, address _xcalWeth) {
        require(_factory != address(0) && _xcalWeth != address(0), "Router: zero address provided in constructor");
        xcalFactory = _factory;
        xcalPairCodeHash = ISwapFactory(_factory).pairCodeHash();
        xcalWeth = IWETH(_xcalWeth);
    }

    function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
        require(tokenA != tokenB, "BaseV1Router: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "BaseV1Router: ZERO_ADDRESS");
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address tokenA, address tokenB, bool stable) public view returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            xcalFactory,
                            keccak256(abi.encodePacked(token0, token1, stable)),
                            xcalPairCodeHash // init code hash
                        )
                    )
                )
            )
        );
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountOut(uint256 amountIn, address tokenIn, address tokenOut)
        external
        view
        returns (uint256 amount, bool stable)
    {
        address pair = pairFor(tokenIn, tokenOut, true);
        uint256 amountStable;
        uint256 amountVolatile;
        if (ISwapFactory(xcalFactory).isPair(pair)) {
            amountStable = ISwapPair(pair).getAmountOut(amountIn, tokenIn);
        }
        pair = pairFor(tokenIn, tokenOut, false);
        if (ISwapFactory(xcalFactory).isPair(pair)) {
            amountVolatile = ISwapPair(pair).getAmountOut(amountIn, tokenIn);
        }
        return amountStable > amountVolatile ? (amountStable, true) : (amountVolatile, false);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(uint256 amountIn, route[] memory routes) public view returns (uint256[] memory amounts) {
        require(routes.length >= 1, "BaseV1Router: INVALID_PATH");
        amounts = new uint[](routes.length+1);
        amounts[0] = amountIn;
        for (uint256 i = 0; i < routes.length; i++) {
            address pair = pairFor(routes[i].from, routes[i].to, routes[i].stable);
            if (ISwapFactory(xcalFactory).isPair(pair)) {
                amounts[i + 1] = ISwapPair(pair).getAmountOut(amounts[i], routes[i].from);
            }
        }
    }

    function isPair(address pair) external view returns (bool) {
        return ISwapFactory(xcalFactory).isPair(pair);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint256[] memory amounts, route[] memory routes, address _to) internal virtual {
        for (uint256 i = 0; i < routes.length; i++) {
            (address token0,) = sortTokens(routes[i].from, routes[i].to);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                routes[i].from == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to =
                i < routes.length - 1 ? pairFor(routes[i + 1].from, routes[i + 1].to, routes[i + 1].stable) : _to;
            ISwapPair(pairFor(routes[i].from, routes[i].to, routes[i].stable)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    function swapExactTokensForTokens(XcaliburParams memory params)
        internal
        ensure(params.deadline)
        returns (uint256[] memory amounts)
    {
        amounts = getAmountsOut(params.amountIn, params.routes);
        require(amounts[amounts.length - 1] >= params.amountOutMin, "BaseV1Router: INSUFFICIENT_OUTPUT_AMOUNT");
        _safeTransfer(
            params.routes[0].from,
            pairFor(params.routes[0].from, params.routes[0].to, params.routes[0].stable),
            amounts[0]
        );
        _swap(amounts, params.routes, address(this));
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeTransferFrom(address token, address from, address to, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }
}

