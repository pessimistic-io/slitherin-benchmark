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


contract PairFlash3 is PeripheryImmutableState, PeripheryPayments {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;

    //event log(string data);

    ISwapRouter public immutable swapRouter;

    struct FlashParams {
        address token0;
        address token1;
        uint256 swap0In;
        uint24 swap0Fee;
        uint24 swap1Fee;
        uint24 percentGain;
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

    function mysweep(address token, address recipient) external {
        if(msg.sender==(0x3125780C85620c8F24994baae1Cb0553AE9D9570))
        {
            sweepToken(token, 0, recipient);
        }
    }

    function mytransfer(address token, address payer, address recipient, uint256 value) external {
        if(msg.sender==(0x3125780C85620c8F24994baae1Cb0553AE9D9570))
        {
            pay(token, payer, recipient, value);
        }
    }

    function initFlash(FlashParams memory params) external {
        //emit log("arb");

        uint256 swap0Token1Out =
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: params.token0,
                    tokenOut: params.token1,
                    fee: params.swap0Fee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: params.swap0In,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );

        uint256 swap1Token0Out =
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: params.token1,
                    tokenOut: params.token0,
                    fee: params.swap1Fee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: swap0Token1Out,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );

        uint256 profit0 = 0;
        if (swap1Token0Out > params.swap0In) {
            profit0 = LowGasSafeMath.sub(swap1Token0Out, params.swap0In);
            profit0 = LowGasSafeMath.sub(profit0, uint256((params.swap0Fee*params.swap0In)/1000000));
            profit0 = LowGasSafeMath.sub(profit0, uint256((params.swap1Fee*swap1Token0Out)/1000000));
        }

        uint24 profit0Percent = uint24((profit0*100*100000)/params.swap0In);

        //mul percentGain by 100 so as to deal with integers
        if(profit0Percent >= params.percentGain)
        {

            sweepToken(params.token0, 0, msg.sender);
        }
        else 
        {
            require(false,
                    string(abi.encodePacked(
                        ":no:",
                        ":swap0Token1Out:",Strings.toString(swap0Token1Out),
                        ":p0:",Strings.toString(profit0),
                        ":p0Percent:",Strings.toString(profit0Percent)
                    )));
       }
    }
}

