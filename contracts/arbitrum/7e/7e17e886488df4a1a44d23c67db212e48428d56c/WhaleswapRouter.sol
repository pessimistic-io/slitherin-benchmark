// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import "./TransferHelper.sol";
import "./IERC20.sol";
import "./IWETH.sol";
import "./WhaleswapFactory.sol";
import "./WhaleswapPair.sol";

contract WhaleswapRouter {
    using SafeMath for uint;

    struct route {
        address from;
        address to;
        bool stable;
    }

    address public immutable factory;
    address public immutable WETH;
    bytes32 immutable pairCodeHash;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'WhaleswapRouter: EXPIRED');
        _;
    }

    constructor(address _factory, address _WETH) {
        factory = _factory;
        pairCodeHash = WhaleswapFactory(_factory).pairCodeHash();
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        require(amountADesired >= amountAMin, "WhaleswapRouter: amountADesired must be greater than or equal to amountAMin");
        require(amountBDesired >= amountBMin, "WhaleswapRouter: amountBDesired must be greater than or equal to amountBMin");

        // create the pair if it doesn't exist yet
        if (WhaleswapFactory(factory).getPair(tokenA, tokenB, stable) == address(0)) {
            WhaleswapFactory(factory).createPair(tokenA, tokenB, stable);
        }
        (uint reserveA, uint reserveB) = getReserves(tokenA, tokenB, stable);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'WhaleswapRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'WhaleswapRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, stable, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = pairFor(tokenA, tokenB, stable);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = WhaleswapPair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        bool stable,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external virtual payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            stable,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = pairFor(token, WETH, stable);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = WhaleswapPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = pairFor(tokenA, tokenB, stable);
        WhaleswapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = WhaleswapPair(pair).burn(to);
        (address token0,) = sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'WhaleswapRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'WhaleswapRouter: INSUFFICIENT_B_AMOUNT');
    }

    function removeLiquidityETH(
        address token,
        bool stable,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            stable,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        bool stable,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual returns (uint amountA, uint amountB) {
        address pair = pairFor(tokenA, tokenB, stable);
        WhaleswapPair(pair).permit(msg.sender, address(this), approveMax ? type(uint).max : liquidity, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, stable, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function removeLiquidityETHWithPermit(
        address token,
        bool stable,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual returns (uint amountToken, uint amountETH) {
        address pair = pairFor(token, WETH, stable);
        uint value = approveMax ? type(uint).max : liquidity;
        WhaleswapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, stable, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        bool stable,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            stable,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        bool stable,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual returns (uint amountETH) {
        address pair = pairFor(token, WETH, stable);
        uint value = approveMax ? type(uint).max : liquidity;
        WhaleswapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, stable, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, route[] memory routes, address _to) internal virtual {
        for (uint i = 0; i < routes.length; i++) {
            (address token0,) = sortTokens(routes[i].from, routes[i].to);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = routes[i].from == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < routes.length - 1 ? pairFor(routes[i+1].from, routes[i+1].to, routes[i+1].stable) : _to;
            WhaleswapPair(pairFor(routes[i].from, routes[i].to, routes[i].stable)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        route[] calldata routes,
        address to,
        uint deadline
    ) external virtual ensure(deadline) returns (uint[] memory amounts) {
        amounts = getAmountsOut(amountIn, routes);

        require(amounts[amounts.length - 1] >= amountOutMin, 'WhaleswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            routes[0].from, msg.sender, pairFor(routes[0].from, routes[0].to, routes[0].stable), amounts[0]
        );
        _swap(amounts, routes, to);
    }

    function swapExactTokensForTokensSimple(
        uint amountIn,
        uint amountOutMin,
        address tokenFrom,
        address tokenTo,
        bool stable,
        address to,
        uint deadline
    ) external ensure(deadline) returns (uint[] memory amounts) {
        route[] memory routes = new route[](1);
        routes[0].from = tokenFrom;
        routes[0].to = tokenTo;
        routes[0].stable = stable;
        amounts = getAmountsOut(amountIn, routes);
        require(amounts[amounts.length - 1] >= amountOutMin, 'WhaleswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            routes[0].from, msg.sender, pairFor(routes[0].from, routes[0].to, routes[0].stable), amounts[0]
        );
        _swap(amounts, routes, to);
    }

    function swapExactETHForTokens(uint amountOutMin, route[] calldata routes, address to, uint deadline)
        external
        virtual
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(routes[0].from == WETH, 'WhaleswapRouter: INVALID_PATH');
        amounts = getAmountsOut(msg.value, routes);
        require(amounts[amounts.length - 1] >= amountOutMin, 'WhaleswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(pairFor(routes[0].from, routes[0].to, routes[0].stable), amounts[0]));
        _swap(amounts, routes, to);
    }

    function swapExactTokensForETH(uint amountIn, uint amountOutMin, route[] calldata routes, address to, uint deadline)
        external
        virtual
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(routes[routes.length - 1].to == WETH, 'WhaleswapRouter: INVALID_PATH');
        amounts = getAmountsOut(amountIn, routes);
        require(amounts[amounts.length - 1] >= amountOutMin, 'WhaleswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            routes[0].from, msg.sender, pairFor(routes[0].from, routes[0].to, routes[0].stable), amounts[0]
        );
        _swap(amounts, routes, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(route[] memory routes, address _to) internal virtual {
        for (uint i; i < routes.length; i++) {
            (address token0, address token1) = sortTokens(routes[i].from, routes[i].to);
            WhaleswapPair pair = WhaleswapPair(pairFor(routes[i].from, routes[i].to, routes[i].stable));

            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput,) = routes[i].from == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            uint amountInput = IERC20(routes[i].from).balanceOf(address(pair)).sub(reserveInput);
            (amountOutput,) = getAmountOut(amountInput, token0, token1);
            }
            (uint amount0Out, uint amount1Out) = routes[i].from == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < routes.length - 1 ? pairFor(routes[i+1].from, routes[i+1].to, routes[i+1].stable) : _to;

            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        route[] calldata routes,
        address to,
        uint deadline
    ) external virtual ensure(deadline) {
        TransferHelper.safeTransferFrom(
            routes[0].from, msg.sender, pairFor(routes[0].from, routes[0].to, routes[0].stable), amountIn
        );
        uint balanceBefore = IERC20(routes[routes.length - 1].to).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(routes, to);
        require(
            IERC20(routes[routes.length - 1].to).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'WhaleswapRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        route[] calldata routes,
        address to,
        uint deadline
    )
        external
        virtual
        payable
        ensure(deadline)
    {
        require(routes[0].from == WETH, 'WhaleswapRouter: INVALID_PATH');
        uint amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(pairFor(routes[0].from, routes[0].to, routes[0].stable), amountIn));
        uint balanceBefore = IERC20(routes[routes.length - 1].to).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(routes, to);
        require(
            IERC20(routes[routes.length - 1].to).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'WhaleswapRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        route[] calldata routes,
        address to,
        uint deadline
    )
        external
        virtual
        ensure(deadline)
    {
        require(routes[routes.length - 1].to == WETH, 'WhaleswapRouter: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            routes[0].from, msg.sender, pairFor(routes[0].from, routes[0].to, routes[0].stable), amountIn
        );
        _swapSupportingFeeOnTransferTokens(routes, address(this));
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'WhaleswapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function isPair(address pair) external view returns (bool) {
        return WhaleswapFactory(factory).isPair(pair);
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'WhaleswapRouter: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'WhaleswapRouter: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address tokenA, address tokenB, bool stable) public view returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1, stable)),
                pairCodeHash // init code hash
            )))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address tokenA, address tokenB, bool stable) public view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = WhaleswapPair(pairFor(tokenA, tokenB, stable)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) public pure returns (uint amountB) {
        require(amountA > 0, 'WhaleswapRouter: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'WhaleswapRouter: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, address tokenIn, address tokenOut) public view returns (uint amountOut, bool stable) {
        require(amountIn > 0, 'WhaleswapRouter: INSUFFICIENT_INPUT_AMOUNT');
        require(tokenIn != address(0) && tokenOut != address(0), 'WhaleswapRouter: INSUFFICIENT_LIQUIDITY');

        address pair = pairFor(tokenIn, tokenOut, true);
        uint amountStable;
        uint amountVolatile;
        if (WhaleswapFactory(factory).isPair(pair)) {
            amountStable = WhaleswapPair(pair).getAmountOut(amountIn, tokenIn);
        }
        pair = pairFor(tokenIn, tokenOut, false);
        if (WhaleswapFactory(factory).isPair(pair)) {
            amountVolatile = WhaleswapPair(pair).getAmountOut(amountIn, tokenIn);
        }
        return amountStable > amountVolatile ? (amountStable, true) : (amountVolatile, false);
    }

    // performs chained getAmountOut calculations on any number of pairs, automatically chooses the most liquid route
    function getAmountsOut(uint amountIn, address[] memory path) public view returns (uint[] memory amounts) {
        require(path.length >= 2, 'WhaleswapRouter: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (amounts[i+1],) = getAmountOut(amounts[i], path[i], path[i+1]);
        }
    }

    // performs chained getAmountOut calculations on any number of pairs, uses routes with specific info on stable pool preference, etc
    function getAmountsOut(uint amountIn, route[] memory routes) public view returns (uint[] memory amounts) {
        require(routes.length >= 1, 'WhaleswapRouter: INVALID_PATH');
        amounts = new uint[](routes.length+1);
        amounts[0] = amountIn;
        for (uint i = 0; i < routes.length; i++) {
            address pair = pairFor(routes[i].from, routes[i].to, routes[i].stable);
            if (WhaleswapFactory(factory).isPair(pair)) {
                amounts[i+1] = WhaleswapPair(pair).getAmountOut(amounts[i], routes[i].from);
            }
        }
    }
}

