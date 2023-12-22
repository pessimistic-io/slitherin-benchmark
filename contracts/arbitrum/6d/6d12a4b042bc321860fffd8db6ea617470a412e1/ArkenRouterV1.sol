// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.8.16;

import "./SafeERC20.sol";
import "./Ownable.sol";

import "./IArkenOptionRewarder.sol";

import "./IUniswapV2Pair.sol";
import "./IArkenPairLongTerm.sol";
import "./IArkenRouter.sol";
import "./IUniswapV2Factory.sol";
import "./ArkenLPLibrary.sol";

// import 'hardhat/console.sol';

contract ArkenRouterV1 is Ownable, IArkenRouter {
    using SafeERC20 for IERC20;

    address public immutable WETH;
    address public factory;
    address public factoryLongTerm;
    address public rewarder;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'ArkenRouter: EXPIRED');
        _;
    }

    constructor(
        address weth_,
        address factory_,
        address factoryLongTerm_,
        address rewarder_
    ) {
        WETH = weth_;
        factory = factory_;
        factoryLongTerm = factoryLongTerm_;
        rewarder = rewarder_;
    }

    function updateRewarder(address rewarder_) external onlyOwner {
        rewarder = rewarder_;
    }

    function updateFactory(address factory_) external onlyOwner {
        factory = factory_;
    }

    function updateFactoryLongTerm(
        address factoryLongTerm_
    ) external onlyOwner {
        factoryLongTerm = factoryLongTerm_;
    }

    function _swapForLiquidity(
        address tokenIn,
        uint256 amountIn,
        address pair,
        address tokenA,
        address tokenB,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        (address token0, address token1) = ArkenLPLibrary.sortTokens(
            tokenA,
            tokenB
        );
        if (tokenIn == token0) {
            (uint256 amount0In, uint256 amount1Out) = ArkenLPLibrary
                .getAmountSwapRetainRatio(pair, tokenIn, amountIn);
            IERC20(token0).safeTransferFrom(msg.sender, pair, amount0In);
            IUniswapV2Pair(pair).swap(0, amount1Out, address(this), '');
            IERC20(token0).safeTransferFrom(
                msg.sender,
                pair,
                amountIn - amount0In
            );
            IERC20(token1).safeTransfer(pair, amount1Out);
            (amountA, amountB) = tokenA == token0
                ? (amountIn - amount0In, amount1Out)
                : (amount1Out, amountIn - amount0In);
        } else {
            (uint256 amount1In, uint256 amount0Out) = ArkenLPLibrary
                .getAmountSwapRetainRatio(pair, tokenIn, amountIn);
            IERC20(token1).safeTransferFrom(msg.sender, pair, amount1In);
            IUniswapV2Pair(pair).swap(amount0Out, 0, address(this), '');
            IERC20(token0).safeTransfer(pair, amount0Out);
            IERC20(token1).safeTransferFrom(
                msg.sender,
                pair,
                amountIn - amount1In
            );
            (amountA, amountB) = tokenA == token0
                ? (amount0Out, amountIn - amount1In)
                : (amountIn - amount1In, amount0Out);
        }
        require(amountAMin <= amountA, 'ArkenRouter: INSUFFICIENT_A_AMOUNT');
        require(amountBMin <= amountB, 'ArkenRouter: INSUFFICIENT_B_AMOUNT');
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        uint256 reserveA,
        uint256 reserveB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = ArkenLPLibrary.quote(
                amountADesired,
                reserveA,
                reserveB
            );
            if (amountBOptimal <= amountBDesired) {
                require(
                    amountBOptimal >= amountBMin,
                    'ArkenRouter: INSUFFICIENT_B_AMOUNT'
                );
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = ArkenLPLibrary.quote(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                assert(amountAOptimal <= amountADesired);
                require(
                    amountAOptimal >= amountAMin,
                    'ArkenRouter: INSUFFICIENT_A_AMOUNT'
                );
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        AddLiquidityData calldata data,
        uint256 deadline
    )
        external
        ensure(deadline)
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        (uint reserveA, uint reserveB) = ArkenLPLibrary.getReserves(
            factory,
            data.tokenA,
            data.tokenB
        );
        (amountA, amountB) = _addLiquidity(
            reserveA,
            reserveB,
            data.amountADesired,
            data.amountBDesired,
            data.amountAMin,
            data.amountBMin
        );
        require(
            data.amountAMin <= amountA,
            'ArkenRouter: INSUFFICIENT_A_AMOUNT'
        );
        require(
            data.amountBMin <= amountB,
            'ArkenRouter: INSUFFICIENT_B_AMOUNT'
        );
        address pair = ArkenLPLibrary.pairFor(
            factory,
            data.tokenA,
            data.tokenB
        );
        IERC20(data.tokenA).safeTransferFrom(msg.sender, pair, amountA);
        IERC20(data.tokenB).safeTransferFrom(msg.sender, pair, amountB);
        liquidity = IUniswapV2Pair(pair).mint(data.to);
    }

    function addLiquiditySingle(
        AddLiquiditySingleData calldata data,
        uint256 deadline
    )
        external
        ensure(deadline)
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        require(
            data.tokenIn == data.tokenA || data.tokenIn == data.tokenB,
            'ArkenRouter: INVALID_TOKEN_IN'
        );
        address pair = ArkenLPLibrary.pairFor(
            factory,
            data.tokenA,
            data.tokenB
        );
        (amountA, amountB) = _swapForLiquidity(
            data.tokenIn,
            data.amountIn,
            pair,
            data.tokenA,
            data.tokenB,
            data.amountAMin,
            data.amountBMin
        );
        liquidity = IUniswapV2Pair(pair).mint(data.to);
    }

    function addLiquidityLongTerm(
        AddLiquidityData calldata addData,
        AddLongTermInputData calldata longtermData,
        uint256 deadline
    )
        external
        ensure(deadline)
        returns (AddLongTermOutputData memory outputData)
    {
        (uint reserveA, uint reserveB) = ArkenLPLibrary.getReserves(
            factoryLongTerm,
            addData.tokenA,
            addData.tokenB
        );
        (outputData.amountA, outputData.amountB) = _addLiquidity(
            reserveA,
            reserveB,
            addData.amountADesired,
            addData.amountBDesired,
            addData.amountAMin,
            addData.amountBMin
        );
        require(
            addData.amountAMin <= outputData.amountA,
            'ArkenRouter: INSUFFICIENT_A_AMOUNT'
        );
        require(
            addData.amountBMin <= outputData.amountB,
            'ArkenRouter: INSUFFICIENT_B_AMOUNT'
        );
        address pair = ArkenLPLibrary.pairFor(
            factoryLongTerm,
            addData.tokenA,
            addData.tokenB
        );
        IERC20(addData.tokenA).safeTransferFrom(
            msg.sender,
            pair,
            outputData.amountA
        );
        IERC20(addData.tokenB).safeTransferFrom(
            msg.sender,
            pair,
            outputData.amountB
        );
        (outputData.liquidity, outputData.positionTokenId) = IArkenPairLongTerm(
            pair
        ).mint(rewarder, longtermData.lockTime);
        IArkenOptionRewarder(rewarder).rewardLongTerm(
            addData.to,
            pair,
            outputData.positionTokenId,
            longtermData.rewardData
        );
    }

    function addLiquidityLongTermSingle(
        AddLiquiditySingleData calldata addData,
        AddLongTermInputData calldata longtermData,
        uint256 deadline
    )
        external
        ensure(deadline)
        returns (AddLongTermOutputData memory outputData)
    {
        require(
            addData.tokenIn == addData.tokenA ||
                addData.tokenIn == addData.tokenB,
            'ArkenRouter: INVALID_TOKEN_IN'
        );
        address pair = ArkenLPLibrary.pairFor(
            factoryLongTerm,
            addData.tokenA,
            addData.tokenB
        );
        (outputData.amountA, outputData.amountB) = _swapForLiquidity(
            addData.tokenIn,
            addData.amountIn,
            pair,
            addData.tokenA,
            addData.tokenB,
            addData.amountAMin,
            addData.amountBMin
        );
        (outputData.liquidity, outputData.positionTokenId) = IArkenPairLongTerm(
            pair
        ).mint(rewarder, longtermData.lockTime);
        IArkenOptionRewarder(rewarder).rewardLongTerm(
            addData.to,
            pair,
            outputData.positionTokenId,
            longtermData.rewardData
        );
    }

    /**
     * REMOVE LIQUIDITY
     */
    function _removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        address to
    ) internal returns (uint256 amountA, uint256 amountB) {
        address pair = ArkenLPLibrary.pairFor(factory, tokenA, tokenB);
        IUniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IUniswapV2Pair(pair).burn(to);
        (address token0, ) = ArkenLPLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0
            ? (amount0, amount1)
            : (amount1, amount0);
    }

    function _removeLiquidityLongTerm(
        address tokenA,
        address tokenB,
        uint256 positionTokenId,
        address to
    ) internal returns (uint256 amountA, uint256 amountB) {
        address pair = ArkenLPLibrary.pairFor(factoryLongTerm, tokenA, tokenB);
        IArkenPairLongTerm(pair).transferFrom(
            msg.sender,
            pair,
            positionTokenId
        ); // send token to pair
        (uint amount0, uint amount1) = IArkenPairLongTerm(pair).burn(
            to,
            positionTokenId
        );
        (address token0, ) = ArkenLPLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0
            ? (amount0, amount1)
            : (amount1, amount0);
    }

    function _returnLiquiditySingle(
        address tokenOut,
        address tokenA,
        address tokenB,
        address pair,
        uint256 amountALiquidity,
        uint256 amountBLiquidity,
        address to
    ) internal returns (uint256 amountA, uint256 amountB) {
        amountA = amountALiquidity;
        amountB = amountBLiquidity;
        (address token0, ) = ArkenLPLibrary.sortTokens(tokenA, tokenB);
        uint256 reserveA;
        uint256 reserveB;
        if (tokenA == token0) {
            (reserveA, reserveB, ) = IUniswapV2Pair(pair).getReserves();
        } else {
            (reserveB, reserveA, ) = IUniswapV2Pair(pair).getReserves();
        }
        uint256 amountOut;
        if (tokenA == tokenOut) {
            amountOut = ArkenLPLibrary.getAmountOut(
                amountB,
                reserveB,
                reserveA
            );
            IERC20(tokenA).safeTransfer(to, amountA);
            IERC20(tokenB).safeTransfer(pair, amountB);
            amountA = amountA + amountOut;
            amountB = 0;
        } else {
            amountOut = ArkenLPLibrary.getAmountOut(
                amountA,
                reserveA,
                reserveB
            );
            IERC20(tokenA).safeTransfer(pair, amountA);
            IERC20(tokenB).safeTransfer(to, amountB);
            amountA = 0;
            amountB = amountB + amountOut;
        }
        if (token0 == tokenOut) {
            IUniswapV2Pair(pair).swap(amountOut, 0, to, '');
        } else {
            IUniswapV2Pair(pair).swap(0, amountOut, to, '');
        }
    }

    function removeLiquidity(
        RemoveLiquidityData calldata data,
        uint256 liquidity,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        (amountA, amountB) = _removeLiquidity(
            data.tokenA,
            data.tokenB,
            liquidity,
            data.to
        );
        require(
            amountA >= data.amountAMin,
            'ArkenRouter: INSUFFICIENT_A_AMOUNT'
        );
        require(
            amountB >= data.amountBMin,
            'ArkenRouter: INSUFFICIENT_B_AMOUNT'
        );
    }

    function removeLiquiditySingle(
        RemoveLiquidityData calldata data,
        address tokenOut,
        uint256 liquidity,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        require(
            tokenOut == data.tokenA || tokenOut == data.tokenB,
            'ArkenRouter: INVALID_TOKEN_OUT'
        );
        (amountA, amountB) = _removeLiquidity(
            data.tokenA,
            data.tokenB,
            liquidity,
            address(this)
        );
        address pair = ArkenLPLibrary.pairFor(
            factory,
            data.tokenA,
            data.tokenB
        );
        (amountA, amountB) = _returnLiquiditySingle(
            tokenOut,
            data.tokenA,
            data.tokenB,
            pair,
            amountA,
            amountB,
            data.to
        );
        require(
            amountA >= data.amountAMin,
            'ArkenRouter: INSUFFICIENT_A_AMOUNT'
        );
        require(
            amountB >= data.amountBMin,
            'ArkenRouter: INSUFFICIENT_B_AMOUNT'
        );
    }

    function removeLiquidityLongTerm(
        RemoveLiquidityData calldata data,
        uint256 positionTokenId,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        (amountA, amountB) = _removeLiquidityLongTerm(
            data.tokenA,
            data.tokenB,
            positionTokenId,
            data.to
        );
        require(
            amountA >= data.amountAMin,
            'ArkenRouter: INSUFFICIENT_A_AMOUNT'
        );
        require(
            amountB >= data.amountBMin,
            'ArkenRouter: INSUFFICIENT_B_AMOUNT'
        );
    }

    function removeLiquidityLongTermSingle(
        RemoveLiquidityData calldata data,
        address tokenOut,
        uint256 positionTokenId,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        require(
            tokenOut == data.tokenA || tokenOut == data.tokenB,
            'ArkenRouter: INVALID_TOKEN_OUT'
        );
        (amountA, amountB) = _removeLiquidityLongTerm(
            data.tokenA,
            data.tokenB,
            positionTokenId,
            address(this)
        );
        address pair = ArkenLPLibrary.pairFor(
            factoryLongTerm,
            data.tokenA,
            data.tokenB
        );
        (amountA, amountB) = _returnLiquiditySingle(
            tokenOut,
            data.tokenA,
            data.tokenB,
            pair,
            amountA,
            amountB,
            data.to
        );
        require(
            amountA >= data.amountAMin,
            'ArkenRouter: INSUFFICIENT_A_AMOUNT'
        );
        require(
            amountB >= data.amountBMin,
            'ArkenRouter: INSUFFICIENT_B_AMOUNT'
        );
    }
}

