// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;
pragma experimental ABIEncoderV2;

import "./Ownable2StepUpgradeable.sol";
import "./Initializable.sol";
import "./SafeMathUpgradeable.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

interface IUniswapV3Factory {
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);

    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external returns (address pool);
}

interface IUniswapV3SwapCallback {
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external;
}

interface ISwapRouter is IUniswapV3SwapCallback {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params)
        external
        payable
        returns (uint256 amountOut);

    struct ExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params)
        external
        payable
        returns (uint256 amountIn);

    struct ExactOutputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
    }

    function exactOutput(ExactOutputParams calldata params)
        external
        payable
        returns (uint256 amountIn);
}

interface IUniswapV3Router is ISwapRouter {
    function refundETH() external payable;

    function factory() external pure returns (address);

    function WETH9() external pure returns (address);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);

    function allPairs(uint) external view returns (address pair);

    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

interface IUniswapV2Pair {
    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}

interface IUniswapV2Router {
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function WETH() external pure returns (address);

    function factory() external pure returns (address);
}

interface IQuoter {
    function quoteExactInput(bytes calldata path, uint256 amountIn)
        external
        returns (uint256 amountOut);

    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountOut);

    function quoteExactOutput(bytes calldata path, uint256 amountOut)
        external
        returns (uint256 amountIn);

    function quoteExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountOut,
        uint160 sqrtPriceLimitX96
    ) external returns (uint256 amountIn);
}

library UniversalERC20 {
    IERC20 public constant ZERO_ADDRESS =
        IERC20(0x0000000000000000000000000000000000000000);
    IERC20 public constant ETH_ADDRESS =
        IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    function universalBalanceOf(IERC20 token, address who)
        public
        view
        returns (uint256)
    {
        if (isETH(token)) {
            return who.balance;
        } else {
            return token.balanceOf(who);
        }
    }

    function isETH(IERC20 token) public pure returns (bool) {
        return (address(token) == address(ZERO_ADDRESS) ||
            address(token) == address(ETH_ADDRESS));
    }
}

library TransferHelper {
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x095ea7b3, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper::safeApprove: approve failed"
        );
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0xa9059cbb, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper::safeTransfer: transfer failed"
        );
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper::transferFrom: transferFrom failed"
        );
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(
            success,
            "TransferHelper::safeTransferETH: ETH transfer failed"
        );
    }
}

contract SwapV2 is Initializable, Ownable2StepUpgradeable {
    using SafeMathUpgradeable for uint256;
    using UniversalERC20 for IERC20;

    IUniswapV2Router public sushiswapRouter;
    IUniswapV2Router public uniswapV2Router;
    IUniswapV3Router public uniswapV3Router;

    IQuoter public uniswapV3Quoter;

    uint24 public poolFee;

    // token addresses for route creation
    address[] public tokens;

    uint256 public reserveCheckMultiplier;

    event Log(string message);
    event LogBytes(bytes message);
    event LogUint(uint message);

    function initialize(
        address _sushiswapRouter,
        address _uniswapV2Router,
        address _uniswapV3Router,
        address _uniswapV3Quoter
    ) initializer public {
        __Ownable2Step_init();
        sushiswapRouter = IUniswapV2Router(_sushiswapRouter);
        uniswapV2Router = IUniswapV2Router(_uniswapV2Router);
        uniswapV3Router = IUniswapV3Router(_uniswapV3Router);
        uniswapV3Quoter = IQuoter(_uniswapV3Quoter); 
        poolFee = 3000;
        reserveCheckMultiplier = 2000;
    }

    function setTokensPath(address[] memory _tokens) external onlyOwner{
        tokens = _tokens;
    }

    /**
     * @dev calculate rate from all three exchanges with auto routing 
     * and perform swapping from best exchange which having sufficient liquidity.
     */
    function swapFromBestExchange(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) public payable returns (uint256) {
        require(amountIn > 0, "Swap: Amount too small to swap");
        require(tokenIn != tokenOut, "Swap: Same tokens");

        (
            uint256 amountOut,
            address[] memory path,
            address router
        ) = getBestExchangeRate(tokenIn, tokenOut, amountIn);

        require(
            amountOut >= amountOutMinimum,
            "Swap: Insufficient output amount"
        );

        uint256 balanceBefore = IERC20(tokenOut).universalBalanceOf(msg.sender);

        if (router == address(uniswapV3Router)) {
            swapV3(uniswapV3Router, tokenIn, path, amountIn, amountOutMinimum);
        } else {
            swapV2(IUniswapV2Router(router), tokenIn, tokenOut, path, amountIn, amountOutMinimum);
        }

        uint256 balanceAfter = IERC20(tokenOut).universalBalanceOf(msg.sender);

        return balanceAfter.sub(balanceBefore);
    }

    /**
     * @dev returns best rate from all three exchanges with auto routing
     */
    function getBestExchangeRate(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    )
        public
        returns (
            uint256 amountOut,
            address[] memory path,
            address router
        )
    {
        (uint256 ssAmountOut, address[] memory ssPath) = getV2Rate(
            sushiswapRouter,
            tokenIn,
            tokenOut,
            amountIn
        );

        (uint256 usV2AmountOut, address[] memory usV2Path) = getV2Rate(
            uniswapV2Router,
            tokenIn,
            tokenOut,
            amountIn
        );

        (uint256 usV3AmountOut, address[] memory usV3Path) = getV3Rate(
            uniswapV3Router,
            tokenIn,
            tokenOut,
            amountIn
        );

        if (usV3AmountOut >= usV2AmountOut && usV3AmountOut >= ssAmountOut) {
            return (usV3AmountOut, usV3Path, address(uniswapV3Router));
        }

        if (usV2AmountOut >= usV3AmountOut && usV2AmountOut >= ssAmountOut) {
            return (usV2AmountOut, usV2Path, address(uniswapV2Router));
        }

        if (ssAmountOut >= usV3AmountOut && ssAmountOut >= usV2AmountOut) {
            return (ssAmountOut, ssPath, address(sushiswapRouter));
        }
    }

    /**
     * @dev Swap tokenIn with tokenOut with given specific V2 router also performs
     * auto routing if pair not exists
     */
    function swapV2(
        IUniswapV2Router router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal {
        require(amountIn > 0, "Swap: Amount too small to swap");

        (uint256 amountOut, address[] memory path) = getV2Rate(
            sushiswapRouter,
            tokenIn,
            tokenOut,
            amountIn
        );

        require(path.length >= 2, "Swap: Route not found");
        require(
            amountOut >= amountOutMinimum,
            "Swap: Insufficient output amount"
        );

        swapV2(router, tokenIn, tokenOut, path, amountIn, amountOutMinimum);
    }

    /**
     * @dev Swap tokens from given path and V2 router
     */
    function swapV2(
        IUniswapV2Router router,
        address tokenIn,
        address tokenOut,
        address[] memory path,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal {
        transferFromAndApprove(tokenIn, address(router), amountIn);

        if (IERC20(tokenIn).isETH()) {
            require(msg.value >= amountIn, "Swap: Insufficient ETH provided");
            router.swapExactETHForTokensSupportingFeeOnTransferTokens{
                value: msg.value
            }(amountOutMinimum, path, msg.sender, block.timestamp);
        } else if (IERC20(tokenOut).isETH()) {
            router.swapExactTokensForETHSupportingFeeOnTransferTokens(
                amountIn,
                amountOutMinimum,
                path,
                msg.sender,
                block.timestamp
            );
        } else {
            router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountIn,
                amountOutMinimum,
                path,
                msg.sender,
                block.timestamp
            );
        }
    }

    /**
     * @dev Swap tokenIn with tokenOut with given V3 router also performs
     * auto routing if pair not exists
     */
    function swapV3(
        IUniswapV3Router router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal {
        require(amountIn > 0, "Swap: Amount too small to swap");

        (uint256 amountOut, address[] memory path) = getV3Rate(
            router,
            tokenIn,
            tokenOut,
            amountIn
        );

        require(path.length >= 2, "Swap: Route not found");
        require(
            amountOut >= amountOutMinimum,
            "Swap: Insufficient output amount"
        );
    }

    /**
     * @dev Swap tokens from given path and V3 router
     */
    function swapV3(
        IUniswapV3Router router,
        address tokenIn,
        address[] memory path,
        uint256 amountIn,
        uint256 amountOutMinimum
    ) internal {
        transferFromAndApprove(tokenIn, address(router), amountIn);

        ISwapRouter.ExactInputParams memory exactInputParams = ISwapRouter
            .ExactInputParams(
                convertToBytesPath(path),
                msg.sender,
                block.timestamp + 15,
                amountIn,
                amountOutMinimum
            );

        if (IERC20(tokenIn).isETH()) {
            require(msg.value >= amountIn, "Swap: Insufficient ETH provided");
            router.exactInput{value: msg.value}(exactInputParams);
            router.refundETH();

            // refund leftover ETH to user
            (bool success, ) = msg.sender.call{value: address(this).balance}(
                ""
            );
            require(success, "refund failed");
        } else {
            router.exactInput(exactInputParams);
        }
    }

    function getV2Rate(
        IUniswapV2Router router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut, address[] memory path) {
        path = getV2Path(router, tokenIn, tokenOut, amountIn);

        if (path.length < 2) return (0, path);

        try router.getAmountsOut(amountIn, path) returns(uint256[] memory amountsOut){
            amountOut = amountsOut[path.length - 1];
        }  catch Error(string memory reason) {
            // catch failing revert() and require()
            emit Log(reason);
        } catch Panic(uint reason) {
            emit LogUint(reason);
        } catch (bytes memory reason) {
            // catch failing assert()
            emit LogBytes(reason);
        }
    }

    function getV3Rate(
        IUniswapV3Router router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal returns (uint256 amountOut, address[] memory path) {
        path = getV3Path(router, tokenIn, tokenOut, amountIn);

        if (path.length < 2) return (0, path);

        try uniswapV3Quoter.quoteExactInput(
            convertToBytesPath(path),
            amountIn
        ) returns(uint256 _amountOut){
            amountOut = _amountOut;
        }  catch Error(string memory reason) {
            // catch failing revert() and require()
            emit Log(reason);
        } catch Panic(uint reason) {
            emit LogUint(reason);
        } catch (bytes memory reason) {
            // catch failing assert()
            emit LogBytes(reason);
        }
    }
 
    function getV2Path(
        IUniswapV2Router router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) private view returns (address[] memory) {
        tokenIn = IERC20(tokenIn).isETH() ? router.WETH() : tokenIn;
        tokenOut = IERC20(tokenOut).isETH() ? router.WETH() : tokenOut;

        address[] memory defaultPath = new address[](2);
        defaultPath[0] = tokenIn;
        defaultPath[1] = tokenOut;

        if (
            pairExists(router, tokenIn, tokenOut) &&
            haveLiquidity(router, tokenIn, tokenOut, amountIn)
        ) return defaultPath;

        return computeV2Path(router, tokenIn, tokenOut);
    }

    function getV3Path(
        IUniswapV3Router router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) private view returns (address[] memory) {
        tokenIn = IERC20(tokenIn).isETH() ? router.WETH9() : tokenIn;
        tokenOut = IERC20(tokenOut).isETH() ? router.WETH9() : tokenOut;

        address[] memory defaultPath = new address[](2);
        defaultPath[0] = tokenIn;
        defaultPath[1] = tokenOut;

        if (
            pairExists(router, tokenIn, tokenOut) &&
            haveLiquidity(router, tokenIn, tokenOut, amountIn)
        ) return defaultPath;

        return computeV3Path(router, tokenIn, tokenOut);
    }

    function computeV2Path(
        IUniswapV2Router router,
        address tokenIn,
        address tokenOut
    ) private view returns (address[] memory) {
        address[] memory _tokens = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (IERC20(tokens[i]).isETH()){
                _tokens[i] = router.WETH();
            } else {
                _tokens[i] = tokens[i];
            }
        }

        for (uint i = 0; i < _tokens.length; i++) {
            if (
                pairExists(router, tokenIn, _tokens[i]) &&
                pairExists(router, _tokens[i], tokenOut)
            ) {
                address[] memory path = new address[](3);
                path[0] = tokenIn;
                path[1] = _tokens[i];
                path[2] = tokenOut;
                return path;
            }
        }

        return new address[](0);
    }

    function computeV3Path(
        IUniswapV3Router router,
        address tokenIn,
        address tokenOut
    ) private view returns (address[] memory) {
        address[] memory _tokens = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (IERC20(tokens[i]).isETH()){
                _tokens[i] = router.WETH9();
            } else {
                _tokens[i] = tokens[i];
            }
        }

        for (uint i = 0; i < _tokens.length; i++) {
            if (
                pairExists(router, tokenIn, _tokens[i]) &&
                pairExists(router, _tokens[i], tokenOut)
            ) {
                address[] memory path = new address[](3);
                path[0] = tokenIn;
                path[1] = _tokens[i];
                path[2] = tokenOut;
                return path;
            }
        }

        return new address[](0);
    }

    function transferFromAndApprove(
        address token,
        address router,
        uint256 amount
    ) private {
        TransferHelper.safeTransferFrom(
            token,
            msg.sender,
            address(this),
            amount
        );

        TransferHelper.safeApprove(token, router, amount);
    }

    function convertToBytesPath(address[] memory path)
        private
        view
        returns (bytes memory bytesPath)
    {
        uint256 i;
        for (i = 0; i < path.length - 1; i++) {
            bytesPath = abi.encodePacked(bytesPath, path[i], poolFee);
        }
        bytesPath = abi.encodePacked(bytesPath, path[i]);
    }

    function pairExists(
        IUniswapV2Router router,
        address tokenA,
        address tokenB
    ) private view returns (bool) {
        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
        return factory.getPair(tokenA, tokenB) != address(0);
    }

    function pairExists(
        IUniswapV3Router router,
        address tokenA,
        address tokenB
    ) private view returns (bool) {
        IUniswapV3Factory factory = IUniswapV3Factory(router.factory());
        return factory.getPool(tokenA, tokenB, poolFee) != address(0);
    }

    /**
     * @dev checks liquidity available on V2 router to swap tokenA with tokenB
     * on basis of reserveCheckMuliplier.
     * @return true if liquidity available otherwise false
     */
    function haveLiquidity(
        IUniswapV2Router router,
        address tokenA,
        address tokenB,
        uint256 amountIn
    ) private view returns (bool) {
        address pairAddress = IUniswapV2Factory(router.factory()).getPair(
            tokenA,
            tokenB
        );
        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();

        if (pair.token0() != tokenA) {
            uint112 temp = reserve0;
            reserve0 = reserve1;
            reserve1 = temp;
        }

        return reserve0 > reserveCheckMultiplier.mul(amountIn).div(1000);
    }

    /**
     * @dev checks liquidity available on V3 router to swap tokenA with tokenB
     * on basis of reserveCheckMuliplier.
     * @return true if liquidity available otherwise false
     */
    function haveLiquidity(
        IUniswapV3Router router,
        address tokenA,
        address tokenB,
        uint256 amountIn
    ) private view returns (bool) {
        address pairAddress = IUniswapV3Factory(router.factory()).getPool(
            tokenA,
            tokenB,
            poolFee
        );
        uint256 reserve0 = IERC20(tokenA).balanceOf(pairAddress);
        return reserve0 > reserveCheckMultiplier.mul(amountIn).div(1000);
    }

    function updateReserveCheckMultiplier(uint256 _reserveCheckMultiplier)
        public
        onlyOwner
    {
        require(
            reserveCheckMultiplier != _reserveCheckMultiplier,
            "Swap: Same state"
        );
        reserveCheckMultiplier = _reserveCheckMultiplier;
    }
}

