// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

//test helper
import "./Test.sol";
//openzeppelin
import "./Create2.sol";
import "./Ownable.sol";
import "./ERC20.sol";
//uniswap
import "./IUniswapV3Factory.sol";
import "./IUniswapV3Pool.sol";
import "./ISwapRouter.sol";
import "./IQuoter.sol";
import "./TransferHelper.sol";
import "./FullMath.sol";
import "./FixedPoint96.sol";

import "./IUniswapV3Pool.sol";
import "./TickMath.sol";

import {UniswapLiquidityManagement} from "./UniswapLiquidityManagement.sol";

import {DepositParams, BurnParams} from "./EnigmaStructs.sol";

//enigma
import "./Enigma.sol";
import "./IEnigmaZapper.sol";
import "./IEnigma.sol";

interface IUniswapRouter is ISwapRouter {
    function refundETH() external payable;
}

/// @title Enigma Zapper
/// @notice Next generation liquidity management protocol ontop of Uniswap v3 Factory
/// @notice Zaps single token into correct proportions of the selected Enigma Pool
/// @author by SteakHut Labs © 2023
contract EnigmaZapper is Ownable {
    using FullMath for uint256;

    IUniswapV3Factory private uniswapFactory;
    IUniswapRouter public constant uniswapRouter = IUniswapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    uint32 public twapDuration;
    //IQuoter public constant quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);

    /// -----------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------

    event EnigmaCreated(address enigmaAddress);
    /// -----------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------

    constructor() {
        //require(_uniswapFactory != address(0), "_uniswapFactory should be non-zero");
        //uniswapFactory = IUniswapV3Factory(_uniswapFactory);
    }

    function _getSqrtRatioX96(address _pool) internal view returns (uint256 sqrtRatioX96) {
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();

        uint256 amount0 = FullMath.mulDiv(pool.liquidity(), FixedPoint96.Q96, sqrtPriceX96);

        uint256 amount1 = FullMath.mulDiv(pool.liquidity(), sqrtPriceX96, FixedPoint96.Q96);

        sqrtRatioX96 = (amount1 * 10 ** ERC20(pool.token0()).decimals()) / amount0;

        console.log(sqrtRatioX96, "sqrtRatioX96");
        return (sqrtRatioX96);
    }

    //getRatio(0x468b88941e7Cc0B88c1869d68ab6b570bCEF62Ff); link/weth
    function performZap(IEnigmaZapper.ZappParams calldata zapParams) external payable returns (uint256 shares) {
        //require(amountIn > 0, "Must pass non 0 amountIn");
        //require(msg.value > 0, "Must pass non 0 ETH amount");

        address tokenIn = zapParams.inputToken;
        console.log(tokenIn, "input tokens");
        //zapParams.swapForToken1 ? address(enigmaPool.token0()) : address(enigmaPool.token1());

        uint256 _token0Decimals = ERC20(zapParams.token0).decimals();
        uint256 _token1Decimals = ERC20(zapParams.token1).decimals();

        //this needs to be the required uniswap pool below is WETH/USDC.e
        //this should be the desired pool in the enigma
        uint256 sqrtRatioX96 = _getSqrtRatioX96(0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443);

        //should be one unit of each token
        (, uint256 amount0, uint256 amount1) = UniswapLiquidityManagement.calcSharesAndAmounts(
            0, 0, 0, 1 * 10 ** _token0Decimals, 1 * 10 ** _token1Decimals
        );
        console.log("wantAmounts:", amount0, amount1);

        uint256 _reqAmount0;
        uint256 _reqAmount1;
        if (amount0 == 0 || amount1 == 0) {
            //set the ratios based on knowing we have no supply of one token
            if (amount0 == 0) {
                _reqAmount1 = zapParams.amountIn;
            } else {
                _reqAmount0 = zapParams.amountIn;
            }
        } else {
            //we know ratio it token0/token1 so.

            uint256 _amount0 = (amount0 * 10 ** _token1Decimals) * (sqrtRatioX96 / (10 ** _token1Decimals));
            uint256 _amount1 = (amount1 * 10 ** _token0Decimals) * 1;

            console.log("_amount0, _amount1", _amount0, _amount1);
            uint256 _total = _amount0 + _amount1;
            console.log(_total, "_total");

            _reqAmount0 = FullMath.mulDiv(zapParams.amountIn, _amount0, _total);
            _reqAmount1 = FullMath.mulDiv(zapParams.amountIn, _amount1, _total);
        }

        console.log(amount0, amount1, "amounts<-");
        console.log("requiredAmounts:", _reqAmount0, _reqAmount1);

        console.log(IERC20(tokenIn).balanceOf(address(this)), "bal of input");
        // Transfer the specified amount of DAI to this contract.
        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), zapParams.amountIn);
        console.log(IERC20(tokenIn).balanceOf(address(this)), "bal of input");
        // Approve the router to spend DAI.
        TransferHelper.safeApprove(tokenIn, address(uniswapRouter), zapParams.amountIn);

        console.log("amounts transferred");

        //perform 2 swaps
        if (_reqAmount1 >= 0 && tokenIn != zapParams.token0) {
            console.log("swap token 0");
            console.log(IERC20(tokenIn).balanceOf(address(this)), "bal of input");
            _performSwap(tokenIn, zapParams.token0, _reqAmount0, 3000, 0);
        }
        if (_reqAmount0 >= 0 && tokenIn != zapParams.token1) {
            console.log("swap token 1");
            console.log(IERC20(tokenIn).balanceOf(address(this)), "bal of input");
            _performSwap(tokenIn, zapParams.token1, _reqAmount1, 3000, 0);
        }

        //deposit the funds into the EnigmaPool
        uint256 bal0 = ERC20(zapParams.token0).balanceOf(address(this));
        uint256 bal1 = ERC20(zapParams.token1).balanceOf(address(this));

        console.log(bal0, bal1, "Balances after swapping");

        DepositParams memory _depParams = DepositParams(bal0, bal1, 0, 0, block.timestamp, address(this), msg.sender);

        TransferHelper.safeApprove(zapParams.token0, address(zapParams.enigmaPool), 2 ** 256 - 1);
        TransferHelper.safeApprove(zapParams.token1, address(zapParams.enigmaPool), 2 ** 256 - 1);

        //deposit into the enigmaPool
        (shares,,) = Enigma(zapParams.enigmaPool).deposit(_depParams);
        console.log(shares);

        _refundAmounts(zapParams.token0, zapParams.token1, zapParams.inputToken);
    }

    function _refundAmounts(address _token0, address _token1, address _inputToken) internal {
        // refund leftover funds to user
        uint256 rem_bal0 = ERC20(_token0).balanceOf(address(this));
        uint256 rem_bal1 = ERC20(_token1).balanceOf(address(this));
        uint256 rem_inputToken = ERC20(_inputToken).balanceOf(address(this));

        console.log("transferAmounts Back");
        console.log(rem_bal0, rem_bal1, rem_inputToken);

        if (rem_bal0 > 0) TransferHelper.safeTransfer(_token0, msg.sender, rem_bal0);
        if (rem_bal1 > 0) TransferHelper.safeTransfer(_token1, msg.sender, rem_bal1);

        //if input token is same as others we will have already sent above
        if (_token0 == _inputToken || _token1 == _inputToken) {
            return;
        } else {
            if (rem_inputToken > 0) TransferHelper.safeTransfer(_inputToken, msg.sender, rem_inputToken);
        }
    }

    function _performSwap(address tokenIn, address tokenOut, uint256 amountIn, uint24 fee, uint256 amountOutMin)
        internal
        returns (uint256 amountOut)
    {
        console.log("Perform Swap", tokenIn, tokenOut, amountIn);
        console.log("Perform Swap", fee, amountOutMin);
        //
        // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
        // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin,
            sqrtPriceLimitX96: 0
        });
        console.log("Params Swap");
        // The call to `exactInputSingle` executes the swap.
        amountOut = uniswapRouter.exactInputSingle(params);

        console.log("Finish Swap amountOut", amountOut);
    }
}

