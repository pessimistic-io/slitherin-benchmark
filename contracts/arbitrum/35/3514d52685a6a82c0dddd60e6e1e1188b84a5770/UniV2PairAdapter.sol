// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

import {OperableKeepable} from "./OperableKeepable.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {IUniswapV2Router} from "./IUniswapV2Router.sol";
import {ILP} from "./ILP.sol";
import {ISwap} from "./ISwap.sol";
import {AssetsPricing} from "./AssetsPricing.sol";

contract UniV2PairAdapter is ILP, OperableKeepable {
    using FixedPointMathLib for uint256;
    using SafeERC20 for IERC20;

    // Needed for stack too deep
    struct AddLiquidity {
        address tokenA;
        address tokenB;
        uint256 amountA;
        uint256 amountB;
    }

    // Info needed to perform a swap
    struct SwapData {
        // Swapper used
        ISwap swapper;
        // Encoded data we are passing to the swap
        bytes data;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  VARIABLES                                 */
    /* -------------------------------------------------------------------------- */

    // @notice Equivalent to 100%
    uint256 public constant BASIS_POINTS = 1e12;

    // @notice Router to perform transactions and liquidity management
    IUniswapV2Router public constant SUSHI_ROUTER = IUniswapV2Router(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    // @notice Wrapped Ether
    IERC20 private constant WETH = IERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    // @notice Non-WETH token for the pair
    IERC20 public otherToken;

    // @notice LP token for a given pair
    IUniswapV2Pair public lp;

    // @notice Tokens contained in the pair
    address public token0;
    address public token1;

    // @notice Slippage in 100%
    uint256 private slippage;

    // @notice Only swap through whitelisted dex'es
    mapping(address => bool) public validSwapper;

    /* -------------------------------------------------------------------------- */
    /*                                    INIT                                    */
    /* -------------------------------------------------------------------------- */

    function initializeLP(address _lp, address _otherToken, uint256 _slippage) external initializer {
        if (_slippage > BASIS_POINTS) {
            revert InvalidSlippage();
        }
        if (_lp == address(0) || _otherToken == address(0)) {
            revert ZeroValue();
        }

        IUniswapV2Pair lp_ = IUniswapV2Pair(_lp);

        lp = lp_;
        otherToken = IERC20(_otherToken);

        token0 = lp_.token0();
        token1 = lp_.token1();

        slippage = _slippage;

        __Governable_init(msg.sender);
    }

    /* -------------------------------------------------------------------------- */
    /*                                ONLY OPERATOR                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Provide liquidity to build LP.
     * @param _wethAmount WETH amount used to build LP.
     * @param _lpData Data needed to swap WETH to build LP.
     * @return Amount of LP Built
     */
    function buildLP(uint256 _wethAmount, LpInfo memory _lpData) public onlyOperator returns (uint256) {
        address WETH_ = address(WETH);

        // Convert half to otherToken to build the Lp token
        uint256 amountToSwap = _wethAmount / 2;

        // Build transaction to swap half of received WETH (token1) to token0
        ISwap.SwapData memory swapData = ISwap.SwapData({
            tokenIn: address(WETH_),
            tokenOut: address(otherToken),
            amountIn: amountToSwap,
            externalData: _lpData.externalData
        });

        // Get dex that will be used to make swap
        address swapper = address(_lpData.swapper);

        WETH.approve(swapper, amountToSwap);

        // Perform swap
        uint256 otherTokenReceived = _lpData.swapper.swap(swapData);

        // Approve Sushi Router to create Lp
        address sushiRouter_ = address(SUSHI_ROUTER);

        WETH.approve(sushiRouter_, amountToSwap);
        otherToken.approve(sushiRouter_, otherTokenReceived);

        uint256 lpReceived = _build(otherTokenReceived, amountToSwap);

        lp.transfer(msg.sender, lpReceived);

        return lpReceived;
    }

    function buildWithBothTokens(address _token0, address _token1, uint256 amount0, uint256 amount1)
        external
        onlyOperator
        returns (uint256)
    {
        IERC20 token0_ = IERC20(_token0);
        IERC20 token1_ = IERC20(_token1);

        token0_.safeTransferFrom(msg.sender, address(this), amount0);
        token1_.safeTransferFrom(msg.sender, address(this), amount1);

        token0_.approve(address(SUSHI_ROUTER), amount0);
        token1_.approve(address(SUSHI_ROUTER), amount1);

        (,, uint256 receivedLp) = SUSHI_ROUTER.addLiquidity(
            address(token0_), address(token1_), amount0, amount1, 0, 0, address(msg.sender), block.timestamp
        );

        return receivedLp;
    }

    /**
     * @notice Remove liquidity from LP and swap for WETH.
     * @param _lpAmount Amount to remove.
     * @param _lpData Swap removed asset for WETH.
     * @return Amount of WETH
     */
    function breakLP(uint256 _lpAmount, LpInfo memory _lpData) external onlyOperator returns (uint256) {
        // Break the chosen amount of LP
        _breakLP(_lpAmount);

        // Swap Other token -> WETH
        if (!validSwapper[address(_lpData.swapper)]) {
            revert InvalidSwapper();
        }

        // Gets amount of token0 after breaking
        uint256 otherTokenReceived = otherToken.balanceOf(address(this));

        // Convert token0 balance to WETH (token1)
        _lpData.swapper.swapTokensToEth(address(otherToken), otherTokenReceived);

        // Store received WETH
        uint256 wethAmount = WETH.balanceOf(address(this));

        WETH.transfer(msg.sender, wethAmount);

        emit BreakLP(address(lp), _lpAmount, wethAmount);

        return wethAmount;
    }

    /**
     * @notice Remove liquidity from LP and swap for WETH.
     * @param _lpAmount LP amount to remove.
     * @param _swapper Swap Contract.
     * @return Amount of WETH
     */
    function performBreakAndSwap(uint256 _lpAmount, ISwap _swapper) external onlyOperator returns (uint256) {
        _breakLP(_lpAmount);

        if (!validSwapper[address(_swapper)]) {
            revert InvalidSwapper();
        }

        // Swap Other token -> WETH
        IUniswapV2Pair _lpToken = lp;
        address _token0 = _lpToken.token0();
        if (_token0 == address(WETH)) {
            IERC20 _token = IERC20(_lpToken.token1());
            uint256 amount = _token.balanceOf(address(this));
            _token.approve(address(_swapper), amount);
            _swapper.swapTokensToEth(_lpToken.token1(), amount);
        } else {
            IERC20 _token = IERC20(_token0);
            uint256 amount = _token.balanceOf(address(this));
            _token.approve(address(_swapper), amount);
            _swapper.swapTokensToEth(_token0, amount);
        }

        uint256 wethBal = IERC20(WETH).balanceOf(address(this));

        IERC20(WETH).transfer(msg.sender, wethBal);

        emit BreakLP(address(_lpToken), _lpAmount, wethBal);

        return wethBal;
    }

    /* -------------------------------------------------------------------------- */
    /*                                  ONLY KEEPER                               */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Swap Assets.
     * @param _swapper Swapper Contract.
     * @param _swapData Data needed to swap.
     */
    function swap(ISwap _swapper, ISwap.SwapData memory _swapData) external onlyKeeper {
        if (!validSwapper[address(_swapper)]) {
            revert InvalidSwapper();
        }

        _swapper.swap(_swapData);
    }

    /* -------------------------------------------------------------------------- */
    /*                                     VIEW                                   */
    /* -------------------------------------------------------------------------- */

    function ETHtoLP(uint256 _amount) external view returns (uint256) {
        return _ETHtoLP(_amount);
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ONLY GOVERNOR                              */
    /* -------------------------------------------------------------------------- */

    function addNewSwapper(address _swapper) external onlyGovernor {
        // Some checks
        if (_swapper == address(0)) {
            revert ZeroAddress();
        }

        validSwapper[_swapper] = true;
        IERC20(token0).safeApprove(_swapper, type(uint256).max);
        IERC20(token1).safeApprove(_swapper, type(uint256).max);
    }

    function updateSlippage(uint256 _slippage) external onlyGovernor {
        if (_slippage > BASIS_POINTS) revert();

        slippage = _slippage;
    }

    /**
     * @notice Moves assets from the strategy to `_to`
     * @param _assets An array of IERC20 compatible tokens to move out from the strategy
     * @param _withdrawNative `true` if we want to move the native asset from the strategy
     */
    function emergencyWithdraw(address _to, address[] memory _assets, bool _withdrawNative) external onlyGovernor {
        uint256 assetsLength = _assets.length;
        for (uint256 i = 0; i < assetsLength; i++) {
            IERC20 asset = IERC20(_assets[i]);
            uint256 assetBalance = asset.balanceOf(address(this));

            if (assetBalance > 0) {
                // Transfer the ERC20 tokens
                asset.transfer(_to, assetBalance);
            }

            unchecked {
                ++i;
            }
        }

        uint256 nativeBalance = address(this).balance;

        // Nothing else to do
        if (_withdrawNative && nativeBalance > 0) {
            // Transfer the native currency
            (bool sent,) = payable(_to).call{value: nativeBalance}("");
            if (!sent) {
                revert FailSendETH();
            }
        }

        emit EmergencyWithdrawal(msg.sender, _to, _assets, _withdrawNative ? nativeBalance : 0);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    PRIVATE                                 */
    /* -------------------------------------------------------------------------- */

    function _validateSlippage(uint256 _amount) private view returns (uint256) {
        // Return minAmountOut
        return (_amount * slippage) / BASIS_POINTS;
    }

    function _breakLP(uint256 _lpAmount) private {
        // Load the LP token for the msg.sender (strategy)
        address lpAddress = address(lp);
        IERC20 lpToken = IERC20(lpAddress);
        uint256 slippage_ = slippage;

        // Few validations
        if (_lpAmount == 0) {
            revert ZeroValue();
        }

        // Use library to calculate an estimate of how much tokens we should receive
        (uint256 desireAmountA, uint256 desireAmountB) = AssetsPricing.breakFromLiquidityAmount(lpAddress, _lpAmount);

        // Approve SUSHI router to spend the LP
        lpToken.safeApprove(address(SUSHI_ROUTER), _lpAmount);

        // Remove liquidity using the numbers above and send to msg.sender and put the real received amounts in the tuple
        SUSHI_ROUTER.removeLiquidity(
            token0,
            token1, // Base token
            _lpAmount,
            desireAmountA.mulDivDown(slippage_, BASIS_POINTS),
            desireAmountB.mulDivDown(slippage_, BASIS_POINTS),
            address(this),
            block.timestamp
        );
    }

    function _build(uint256 otherTokenAmount, uint256 wethAmount) private returns (uint256) {
        AddLiquidity memory liquidityParams;

        address _otherToken = address(otherToken);

        if (_otherToken == token0) {
            liquidityParams.tokenA = _otherToken;
            liquidityParams.tokenB = address(WETH);
            liquidityParams.amountA = otherTokenAmount;
            liquidityParams.amountB = wethAmount;
        } else {
            liquidityParams.tokenA = address(WETH);
            liquidityParams.tokenB = _otherToken;
            liquidityParams.amountA = wethAmount;
            liquidityParams.amountB = otherTokenAmount;
        }

        // Use SUSHI router to add liquidity using the outputs of the 1inch swaps
        (,, uint256 liquidity) = SUSHI_ROUTER.addLiquidity(
            liquidityParams.tokenA,
            liquidityParams.tokenB,
            liquidityParams.amountA,
            liquidityParams.amountB,
            _validateSlippage(liquidityParams.amountA),
            _validateSlippage(liquidityParams.amountB),
            address(this),
            block.timestamp
        );

        emit BuildLP(
            liquidityParams.tokenA,
            liquidityParams.tokenB,
            liquidityParams.amountA,
            liquidityParams.amountB,
            address(lp),
            liquidity
        );

        // Return the new balance of msg.sender of the LP just created
        return liquidity;
    }

    /**
     * @notice Quotes zap in amount for adding liquidity pair from `_inputToken`.
     * @param _amount The amount of liquidity to calculate output
     * @return estimation of amount of LP tokens that will be available when zapping in.
     */
    function _ETHtoLP(uint256 _amount) private view returns (uint256) {
        IUniswapV2Pair _lp = lp;

        (uint112 reserveA, uint112 reserveB,) = _lp.getReserves();
        uint256 amountADesired;
        uint256 amountBDesired;

        if (token0 == address(WETH)) {
            amountADesired = _amount / 2;
            amountBDesired = SUSHI_ROUTER.quote(amountADesired, reserveA, reserveB);
        } else {
            amountBDesired = _amount / 2;
            amountADesired = SUSHI_ROUTER.quote(amountBDesired, reserveB, reserveA);
        }

        uint256 _totalSupply = _lp.totalSupply();

        uint256 liquidityA = amountADesired.mulDivDown(_totalSupply, reserveA);
        uint256 liquidityB = amountBDesired.mulDivDown(_totalSupply, reserveB);

        return liquidityA < liquidityB ? liquidityA : liquidityB;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    event BuildLP(
        address indexed token0,
        address indexed token1,
        uint256 amountToken0,
        uint256 amountToken1,
        address indexed lpAddress,
        uint256 lpAmount
    );
    event BreakLP(address indexed lpAddress, uint256 lpAmount, uint256 wethAmount);
    event EmergencyWithdrawal(address indexed caller, address indexed receiver, address[] tokens, uint256 nativeBalanc);

    /* -------------------------------------------------------------------------- */
    /*                                    ERRORS                                  */
    /* -------------------------------------------------------------------------- */

    error ZeroValue();
    error ZeroAddress();
    error InvalidSwapper();
    error InvalidSlippage();
    error FailSendETH();
}

