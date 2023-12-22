// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;

import "./WhiteholeLibrary.sol";
import "./SafeToken.sol";
import "./interfaces_IWETH.sol";
import "./IWhiteholeFactory.sol";
import "./IWhiteholeRouter.sol";

contract WhiteholeRouter is IWhiteholeRouter {
    using SafeMath for uint256;
    using SafeToken for address;

    address public immutable override factory;
    address public immutable override WETH;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "WhiteholeRouter: EXPIRED");
        _;
    }

    constructor(address _factory, address _WETH) public {
        factory = _factory;
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        // create the pair if it doesn't exist yet
        if (IWhiteholeFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IWhiteholeFactory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = WhiteholeLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = WhiteholeLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "WhiteholeRouter: INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = WhiteholeLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "WhiteholeRouter: INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    // Adds liquidity to an ERC20-ERC20 Pool
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = WhiteholeLibrary.pairFor(factory, tokenA, tokenB);
        SafeToken.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        SafeToken.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IWhiteholePair(pair).mint(to);
    }

    // Adds liquidity to an ERC20-WETH Pool with ETH
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );

        address pair = WhiteholeLibrary.pairFor(factory, token, WETH);
        SafeToken.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IWhiteholePair(pair).mint(to);
        // refund dust ETH, if any
        if (msg.value > amountETH) SafeToken.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = WhiteholeLibrary.pairFor(factory, tokenA, tokenB);

        IWhiteholePair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint256 amount0, uint256 amount1) = IWhiteholePair(pair).burn(to);
        (address token0, ) = WhiteholeLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "WhiteholeRouter: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "WhiteholeRouter: INSUFFICIENT_B_AMOUNT");
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        SafeToken.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        SafeToken.safeTransferETH(to, amountETH);
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = WhiteholeLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2 ? WhiteholeLibrary.pairFor(factory, output, path[i + 2]) : _to;
            IWhiteholePair(WhiteholeLibrary.pairFor(factory, input, output)).swap(
                amount0Out,
                amount1Out,
                to,
                new bytes(0)
            );
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = WhiteholeLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "WhiteholeRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        SafeToken.safeTransferFrom(
            path[0],
            msg.sender,
            WhiteholeLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = WhiteholeLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "WhiteholeRouter: EXCESSIVE_INPUT_AMOUNT");
        SafeToken.safeTransferFrom(
            path[0],
            msg.sender,
            WhiteholeLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == WETH, "WhiteholeRouter: INVALID_PATH");
        amounts = WhiteholeLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "WhiteholeRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(WhiteholeLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WETH, "WhiteholeRouter: INVALID_PATH");
        amounts = WhiteholeLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "WhiteholeRouter: EXCESSIVE_INPUT_AMOUNT");
        SafeToken.safeTransferFrom(
            path[0],
            msg.sender,
            WhiteholeLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        SafeToken.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WETH, "WhiteholeRouter: INVALID_PATH");
        amounts = WhiteholeLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "WhiteholeRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        SafeToken.safeTransferFrom(
            path[0],
            msg.sender,
            WhiteholeLibrary.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        SafeToken.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override ensure(deadline) returns (uint256[] memory amounts) {
        require(path[0] == WETH, "WhiteholeRouter: INVALID_PATH");
        amounts = WhiteholeLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, "WhiteholeRouter: EXCESSIVE_INPUT_AMOUNT");
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(WhiteholeLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust ETH, if any
        if (msg.value > amounts[0]) SafeToken.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public pure virtual override returns (uint256 amountB) {
        return WhiteholeLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountOut) {
        return WhiteholeLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual override returns (uint256 amountIn) {
        return WhiteholeLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(
        uint256 amountIn,
        address[] memory path
    ) public view virtual override returns (uint256[] memory amounts) {
        return WhiteholeLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(
        uint256 amountOut,
        address[] memory path
    ) public view virtual override returns (uint256[] memory amounts) {
        return WhiteholeLibrary.getAmountsIn(factory, amountOut, path);
    }
}

