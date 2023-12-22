// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "./IUniswapV3FlashCallback.sol";
import "./LowGasSafeMath.sol";

import "./PeripheryPayments.sol";
import "./PeripheryImmutableState.sol";
import "./PoolAddress.sol";
import "./CallbackValidation.sol";
import "./TransferHelper.sol";
import "./ISwapRouter.sol";
import "./Strings.sol";
import "./StringUtils.sol";


contract PairFlash2 is IUniswapV3FlashCallback, PeripheryImmutableState, PeripheryPayments {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;

    event log(string data);

    ISwapRouter public immutable swapRouter;

    struct FlashParams {
        address token0;
        address token1;
        address token2;
        uint24 flashFee;
        uint256 amount0;
        uint256 amount1;
        uint24 swap0Fee;
        uint24 swap1Fee;
        uint24 swap2Fee;
        uint24 percentGain;
        address flashToken0;
        address flashToken1;
        uint256 flashAmount0;
        uint256 flashAmount1;
    }

    struct FlashCallbackData {
        uint256 amount0;
        uint256 amount1;
        address payer;
        PoolAddress.PoolKey poolKey;
        uint24 swap0Fee;
        uint24 swap1Fee;
        uint24 swap2Fee;
        uint24 percentGain;
        address token0;
        address token1;
        address token2;
    }

    struct ApproveData {
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
        address swapRouter;
    }

    constructor(
        ISwapRouter _swapRouter,
        address _factory,
        address _WETH9
    ) PeripheryImmutableState(_factory, _WETH9) {
        swapRouter = _swapRouter;
    }

    function myapprove(ApproveData memory params) external {
        if(msg.sender==(0x3125780C85620c8F24994baae1Cb0553AE9D9570))
        {
            TransferHelper.safeApprove(params.token0, address(params.swapRouter), params.amount0);
            TransferHelper.safeApprove(params.token1, address(params.swapRouter), params.amount1);
            TransferHelper.safeApprove(params.token0, address(this), params.amount0);
            TransferHelper.safeApprove(params.token1, address(this), params.amount1);
        }
    }

    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external override {

        FlashCallbackData memory decoded = abi.decode(data, (FlashCallbackData));
        CallbackValidation.verifyCallback(factory, decoded.poolKey);

        if(decoded.poolKey.token0!=decoded.token0)
        {
            uint256 tmp = fee0;
            fee0 = fee1;
            fee1 = tmp;
        }

        uint256 amount1Min = LowGasSafeMath.add(decoded.amount1, fee1);

        uint256 swap0Token1Out =
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: decoded.token0,
                    tokenOut: decoded.token1,
                    fee: decoded.swap0Fee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: decoded.amount0,
                    amountOutMinimum: amount1Min,
                    sqrtPriceLimitX96: 0
                })
            );

        uint256 swap1Token1In = LowGasSafeMath.sub(swap0Token1Out, fee1);
        swap1Token1In = LowGasSafeMath.sub(swap1Token1In, uint256((decoded.swap1Fee*swap1Token1In)/1000000));
        uint256 swap1Token0Out =
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: decoded.token1,
                    tokenOut: decoded.token0,
                    fee: decoded.swap1Fee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: swap1Token1In,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );

        uint256 amount0Owed = LowGasSafeMath.add(decoded.amount0, fee0);

        uint256 profit0 = 0;
        if (swap1Token0Out > amount0Owed) {
            profit0 = LowGasSafeMath.sub(swap1Token0Out, amount0Owed);
            profit0 = LowGasSafeMath.sub(profit0, uint256((decoded.swap0Fee*decoded.amount0)/1000000));
            profit0 = LowGasSafeMath.sub(profit0, uint256((decoded.swap1Fee*swap1Token0Out)/1000000));
        }

        uint24 profit0Percent = uint24((profit0*100*100000)/decoded.amount0);

        //mul percentGain by 100 so as to deal with integers
        if(profit0Percent >= decoded.percentGain)
        {
            uint256 amount1Owed = LowGasSafeMath.add(decoded.amount1, fee1);

            //msg.sender is the pool from which we get flash loan
            if (amount0Owed > 0) pay(decoded.token0, address(this), msg.sender, amount0Owed);
            if (amount1Owed > 0) pay(decoded.token1, address(this), msg.sender, amount1Owed);

            //this is this contract address
            //pay(decoded.token0, address(this), decoded.payer, profit0);
            sweepToken(decoded.token0, 0, decoded.payer);

            uint256 balanceToken = IERC20(decoded.token1).balanceOf(address(this));
            if(balanceToken > 0) {
                sweepToken(decoded.token1, 0, decoded.payer);
            }
        }
        else 
        {
            require(false,
                    string(abi.encodePacked(
                        ":no:",
                        ":swap0Token1Out:",Strings.toString(swap0Token1Out),
                        ":swap1Token1In:",Strings.toString(swap1Token1In),
                        ":swap1Token0Out:",Strings.toString(swap1Token1In), 
                        ":amount0Owed:",Strings.toString(amount0Owed),
                        ":p0:",Strings.toString(profit0),
                        ":p0Percent:",Strings.toString(profit0Percent)
                    )));
       }
    }

    function initFlash(FlashParams memory params) external {
        PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({token0: params.flashToken0, token1: params.flashToken1, fee: params.flashFee});
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));

        //sender is one who sends message
        //this is contract address
        pool.flash(
            address(this),
            params.flashAmount0,
            params.flashAmount1,
            abi.encode(
                FlashCallbackData({
                    amount0: params.amount0,
                    amount1: params.amount1,
                    payer: msg.sender,
                    poolKey: poolKey,
                    swap0Fee: params.swap0Fee,
                    swap1Fee: params.swap1Fee,
                    swap2Fee: params.swap2Fee,
                    percentGain: params.percentGain,
                    token0: params.token0,
                    token1: params.token1,
                    token2: params.token2
                })
            )
        );
    }
}

