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

contract PairFlash is IUniswapV3FlashCallback, PeripheryImmutableState, PeripheryPayments {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;

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
        address token;
        uint256 amount;
        address contractAddress;
    }

    event log(string data);

    ISwapRouter public immutable swapRouter;

    constructor(
        ISwapRouter _swapRouter,
        address _factory,
        address _WETH9
    ) PeripheryImmutableState(_factory, _WETH9) {
        swapRouter = _swapRouter;
    }

    function approve(ApproveData memory params) external {
        //if(msg.sender==(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266))
        if(msg.sender==(0x3125780C85620c8F24994baae1Cb0553AE9D9570))
        {
            TransferHelper.safeApprove(params.token, address(params.contractAddress), params.amount);
        }
        else
        {
            require(false, "approveFail");
        }
    }

    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external override {
        emit log("uniswapV3FlashCallback");

        FlashCallbackData memory decoded = abi.decode(data, (FlashCallbackData));
        CallbackValidation.verifyCallback(factory, decoded.poolKey);

        if(decoded.poolKey.token0!=decoded.token0)
        {
            uint256 tmp = fee0;
            fee0 = fee1;
            fee1 = tmp;
        }

        uint256 amount1Min = LowGasSafeMath.add(decoded.amount1, fee1);

        emit log("START SWAP 0");
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

        emit log("START SWAP 1");
        uint256 swap1Token1In = LowGasSafeMath.sub(swap0Token1Out, fee1);
        swap1Token1In = LowGasSafeMath.sub(swap1Token1In, uint256((decoded.swap1Fee*swap1Token1In)/1000000));
        uint256 swap1Token2Out =
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: decoded.token1,
                    tokenOut: decoded.token2,
                    fee: decoded.swap1Fee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: swap1Token1In,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );

        emit log("START SWAP 2");
        uint256 amount0Min = LowGasSafeMath.add(decoded.amount0, fee0);
        uint256 swap2Token0Out =
            swapRouter.exactInputSingle(
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: decoded.token2,
                    tokenOut: decoded.token0,
                    fee: decoded.swap2Fee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: swap1Token2Out,
                    amountOutMinimum: amount0Min,
                    sqrtPriceLimitX96: 0
                })
            );

        uint256 amount0Owed = LowGasSafeMath.add(decoded.amount0, fee0);

        uint256 profit0 = 0;
        if (swap2Token0Out > amount0Owed) {
            profit0 = LowGasSafeMath.sub(swap2Token0Out, amount0Owed);
            profit0 = LowGasSafeMath.sub(profit0, uint256((decoded.swap0Fee*decoded.amount0)/1000000));
            profit0 = LowGasSafeMath.sub(profit0, uint256((decoded.swap2Fee*swap2Token0Out)/1000000));
        }

        uint24 profit0Percent = uint24((profit0*100*100000)/decoded.amount0);

        //mul percentGain by 100 so as to deal with integers
        if(profit0Percent >= decoded.percentGain)
        {
            emit log("yes");

            uint256 amount1Owed = LowGasSafeMath.add(decoded.amount1, fee1);
            if (amount0Owed > 0) pay(decoded.token0, address(this), msg.sender, amount0Owed);
            if (amount1Owed > 0) pay(decoded.token1, address(this), msg.sender, amount1Owed);

            sweepToken(decoded.token0, 0, decoded.payer);

            uint256 balanceToken = IERC20(decoded.token1).balanceOf(address(this));
            if(balanceToken > 0) {
                sweepToken(decoded.token1, 0, decoded.payer);
            }
        }
        else
        {
            emit log("no");
            require(false, 
                    string(abi.encodePacked(
                        "no",
                        ":amount0:",Strings.toString(decoded.amount0),":swap0Token1Out:",Strings.toString(swap0Token1Out),
                        ":swap1Token1In:",Strings.toString(swap1Token1In),":swap1Token2Out:",Strings.toString(swap1Token2Out),
                        ":swap2Token0Out:",Strings.toString(swap2Token0Out),
                        ":profit0:",Strings.toString(profit0),
                        ":profit0Percent:",Strings.toString(profit0Percent)
                    )));
        }
    }

    function initFlash(FlashParams memory params) external {
        PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({token0: params.flashToken0, token1: params.flashToken1, fee: params.flashFee});
        IUniswapV3Pool pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));

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

