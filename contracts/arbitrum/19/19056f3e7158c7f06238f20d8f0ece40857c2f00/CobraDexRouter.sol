// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.12;

import "./CobraDexLibrary.sol";
import "./SafeMath.sol";
import "./TransferHelper.sol";
import "./ICobraDexRouter.sol";
import "./ICobraDexFactory.sol";
import "./IERC20.sol";
import "./IWETH.sol";
import "./IRebateEstimator.sol";
import { Ownable } from "./Ownable.sol";

contract CobraDexRouter is ICobraDexRouter, IRebateEstimator {
    using SafeMathUniswap for uint;

    address public immutable override factory;
    address public immutable override WETH;
    address public rebateEstimator;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'CobraDexRouter: EXPIRED');
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
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (ICobraDexFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            ICobraDexFactory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = CobraDexLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = CobraDexLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'CobraDexRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = CobraDexLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'CobraDexRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = CobraDexLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = ICobraDexPair(pair).mint(to);
    }
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountETH, uint liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );
        address pair = CobraDexLibrary.pairFor(factory, token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = ICobraDexPair(pair).mint(to);
        // refund dust eth, if any
        if (msg.value > amountETH) TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = CobraDexLibrary.pairFor(factory, tokenA, tokenB);
        ICobraDexPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = ICobraDexPair(pair).burn(to);
        (address token0,) = CobraDexLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'CobraDexRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'CobraDexRouter: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
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
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        address pair = CobraDexLibrary.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? type(uint256).max : liquidity;
        ICobraDexPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountToken, uint amountETH) {
        address pair = CobraDexLibrary.pairFor(factory, token, WETH);
        uint value = approveMax ? type(uint256).max : liquidity;
        ICobraDexPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20Uniswap(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        TransferHelper.safeTransferETH(to, amountETH);
    }
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountETH) {
        address pair = CobraDexLibrary.pairFor(factory, token, WETH);
        uint value = approveMax ? type(uint256).max : liquidity;
        ICobraDexPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swapWithoutRebate(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = CobraDexLibrary.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? CobraDexLibrary.pairFor(factory, output, path[i + 2]) : _to;
            ICobraDexPair(CobraDexLibrary.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    function _swapWithRebate(uint[] memory amounts, address[] memory path, address _to, uint64 feeRebate) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = CobraDexLibrary.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? CobraDexLibrary.pairFor(factory, output, path[i + 2]) : _to;
            ICobraDexPair(CobraDexLibrary.pairFor(factory, input, output)).swapWithRebate(
                amount0Out, amount1Out, to, feeRebate, new bytes(0)
            );
        }
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline,
        bool useRebate
    ) external virtual override ensure(deadline) mevControl returns (uint[] memory amounts) {
        uint64 feeRebate = useRebate ? getRebate(to) : 0;
        amounts = CobraDexLibrary.getAmountsOut(factory, amountIn, path, feeRebate);
        require(amounts[amounts.length - 1] >= amountOutMin, 'CobraDexRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CobraDexLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        if (useRebate) {
            _swapWithRebate(amounts, path, to, feeRebate);
        } else {
            _swapWithoutRebate(amounts, path, to);
        }
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline,
        bool useRebate
    ) external virtual override ensure(deadline) mevControl returns (uint[] memory amounts) {
        uint64 feeRebate = useRebate ? getRebate(to) : 0;
        amounts = CobraDexLibrary.getAmountsIn(factory, amountOut, path, feeRebate);
        require(amounts[0] <= amountInMax, 'CobraDexRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CobraDexLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        if (useRebate) {
            _swapWithRebate(amounts, path, to, feeRebate);
        } else {
            _swapWithoutRebate(amounts, path, to);
        }
    }
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline, bool useRebate)
        external
        virtual
        override
        payable
        ensure(deadline)
        mevControl
        returns (uint[] memory amounts)
    {
        uint64 feeRebate = useRebate ? getRebate(to) : 0;
        require(path[0] == WETH, 'CobraDexRouter: INVALID_PATH');
        amounts = CobraDexLibrary.getAmountsOut(factory, msg.value, path, feeRebate);
        require(amounts[amounts.length - 1] >= amountOutMin, 'CobraDexRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(CobraDexLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        if (useRebate) {
            _swapWithRebate(amounts, path, to, feeRebate);
        } else {
            _swapWithoutRebate(amounts, path, to);
        }
    }
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline, bool useRebate)
        external
        virtual
        override
        ensure(deadline)
        mevControl
        returns (uint[] memory amounts)
    {
        uint64 feeRebate = useRebate ? getRebate(to) : 0;
        require(path[path.length - 1] == WETH, 'CobraDexRouter: INVALID_PATH');
        amounts = CobraDexLibrary.getAmountsIn(factory, amountOut, path, feeRebate);
        require(amounts[0] <= amountInMax, 'CobraDexRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CobraDexLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        if (useRebate) {
            _swapWithRebate(amounts, path, address(this), feeRebate);
        } else {
            _swapWithoutRebate(amounts, path, address(this));
        }
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline, bool useRebate)
        external
        virtual
        override
        ensure(deadline)
        mevControl
        returns (uint[] memory amounts)
    {
        uint64 feeRebate = useRebate ? getRebate(to) : 0;
        require(path[path.length - 1] == WETH, 'CobraDexRouter: INVALID_PATH');
        amounts = CobraDexLibrary.getAmountsOut(factory, amountIn, path, feeRebate);
        require(amounts[amounts.length - 1] >= amountOutMin, 'CobraDexRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CobraDexLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        if (useRebate) {
            _swapWithRebate(amounts, path, address(this), feeRebate);
        } else {
            _swapWithoutRebate(amounts, path, address(this));
        }
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline, bool useRebate)
        external
        virtual
        override
        payable
        ensure(deadline)
        mevControl
        returns (uint[] memory amounts)
    {
        uint64 feeRebate = useRebate ? getRebate(to) : 0;
        require(path[0] == WETH, 'CobraDexRouter: INVALID_PATH');
        amounts = CobraDexLibrary.getAmountsIn(factory, amountOut, path, feeRebate);
        require(amounts[0] <= msg.value, 'CobraDexRouter: EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(CobraDexLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        if (useRebate) {
            _swapWithRebate(amounts, path, to, getRebate(to));
        } else {
            _swapWithoutRebate(amounts, path, to);
        }
        // refund dust eth, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokensWithoutRebate(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = CobraDexLibrary.sortTokens(input, output);
            ICobraDexPair pair = ICobraDexPair(CobraDexLibrary.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput,) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20Uniswap(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = CobraDexLibrary.getAmountOut(factory, amountInput, input, output, 0);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? CobraDexLibrary.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokensWithRebate(address[] memory path, address _to, uint64 feeRebate) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = CobraDexLibrary.sortTokens(input, output);
            ICobraDexPair pair = ICobraDexPair(CobraDexLibrary.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput,) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IERC20Uniswap(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = CobraDexLibrary.getAmountOut(factory, amountInput, input, output, feeRebate);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? CobraDexLibrary.pairFor(factory, output, path[i + 2]) : _to;
            pair.swapWithRebate(amount0Out, amount1Out, to, feeRebate, new bytes(0));
        }
    }
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline,
        bool useRebate
    ) external virtual override ensure(deadline) mevControl {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CobraDexLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IERC20Uniswap(path[path.length - 1]).balanceOf(to);
        if (useRebate) {
            _swapSupportingFeeOnTransferTokensWithRebate(path, to, getRebate(to));
        } else {
            _swapSupportingFeeOnTransferTokensWithoutRebate(path, to);
        }
        require(
            IERC20Uniswap(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'CobraDexRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline,
        bool useRebate
    )
        external
        virtual
        override
        payable
        ensure(deadline)
        mevControl
    {
        require(path[0] == WETH, 'CobraDexRouter: INVALID_PATH');
        uint amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(CobraDexLibrary.pairFor(factory, path[0], path[1]), amountIn));
        uint balanceBefore = IERC20Uniswap(path[path.length - 1]).balanceOf(to);
        if (useRebate) {
            _swapSupportingFeeOnTransferTokensWithRebate(path, to, getRebate(to));
        } else {
            _swapSupportingFeeOnTransferTokensWithoutRebate(path, to);
        }
        require(
            IERC20Uniswap(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'CobraDexRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline,
        bool useRebate
    )
        external
        virtual
        override
        ensure(deadline)
        mevControl
    {
        require(path[path.length - 1] == WETH, 'CobraDexRouter: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, CobraDexLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        if (useRebate) {
            _swapSupportingFeeOnTransferTokensWithRebate(path, address(this), getRebate(to));
        } else {
            _swapSupportingFeeOnTransferTokensWithoutRebate(path, address(this));
        }
        uint amountOut = IERC20Uniswap(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'CobraDexRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
    }

    modifier mevControl() {
        ICobraDexFactory(factory).mevControlPre(msg.sender);
        _;
        ICobraDexFactory(factory).mevControlPost(msg.sender);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return CobraDexLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountsOut(uint amountIn, address[] memory path, bool useRebate)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {

        uint64 feeRebate = (useRebate ? getRebate(msg.sender) : 0);
        return CobraDexLibrary.getAmountsOut(factory, amountIn, path, feeRebate);
    }

    function getAmountsIn(uint amountOut, address[] memory path, bool useRebate)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        uint64 feeRebate = (useRebate ? getRebate(msg.sender) : 0);
        return CobraDexLibrary.getAmountsIn(factory, amountOut, path, feeRebate);
    }

    function setRebateEstimator(address _rebateEstimator) external {
        require(Ownable(factory).owner() == msg.sender, 'CobraDexRouter: FORBIDDEN');
        rebateEstimator = _rebateEstimator;
    }

    function getRebate(address recipient) public override view returns (uint64) {
        if (rebateEstimator == address(0x0)) {
            return 0;
        }
        return IRebateEstimator(rebateEstimator).getRebate(recipient);
    }
}

