// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "./IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {SushiAdapter} from "./SushiAdapter.sol";
import {I1inchAggregationRouterV4} from "./I1inchAggregationRouterV4.sol";
import {Babylonian} from "./Babylonian.sol";
import {IStableSwap} from "./IStableSwap.sol";
import {Curve2PoolAdapter} from "./Curve2PoolAdapter.sol";

library OneInchZapLib {
    using Curve2PoolAdapter for IStableSwap;
    using SafeERC20 for IERC20;
    using SushiAdapter for IUniswapV2Router02;

    enum ZapType {
        ZAP_IN,
        ZAP_OUT
    }

    struct SwapParams {
        address caller;
        I1inchAggregationRouterV4.SwapDescription desc;
        bytes data;
    }

    struct ZapInIntermediateParams {
        SwapParams swapFromIntermediate;
        SwapParams toPairTokens;
        address pairAddress;
        uint256 token0Amount;
        uint256 token1Amount;
        uint256 minPairTokens;
    }

    struct ZapInParams {
        SwapParams toPairTokens;
        address pairAddress;
        uint256 token0Amount;
        uint256 token1Amount;
        uint256 minPairTokens;
    }

    IUniswapV2Router02 public constant sushiSwapRouter = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    IStableSwap public constant crv2 = IStableSwap(0x7f90122BF0700F9E7e1F688fe926940E8839F353);

    uint256 private constant deadline = 0xf000000000000000000000000000000000000000000000000000000000000000;

    /**
     * @notice Add liquidity to Sushiswap pools with ETH/ERC20 Tokens
     */
    function zapInIntermediate(
        I1inchAggregationRouterV4 self,
        SwapParams calldata _swapFromIntermediate,
        SwapParams calldata _toPairTokens,
        address _pairAddress,
        uint256 _token0Amount,
        uint256 _token1Amount,
        uint256 _minPairTokens
    )
        public
        returns (uint256)
    {
        address[2] memory pairTokens = [IUniswapV2Pair(_pairAddress).token0(), IUniswapV2Pair(_pairAddress).token1()];

        // The dest token should be one of the tokens on the pair
        if (
            (_toPairTokens.desc.dstToken != pairTokens[0] && _toPairTokens.desc.dstToken != pairTokens[1])
                || (_swapFromIntermediate.desc.dstToken != pairTokens[0] && _swapFromIntermediate.desc.dstToken != pairTokens[1])
        ) {
            revert INVALID_DEST_TOKEN();
        }

        perform1InchSwap(self, _swapFromIntermediate);

        if (_toPairTokens.desc.srcToken != pairTokens[0] && _toPairTokens.desc.srcToken != pairTokens[1]) {
            revert INVALID_SOURCE_TOKEN();
        }

        uint256 swapped = zapIn(self, _toPairTokens, _pairAddress, _token0Amount, _token1Amount, _minPairTokens);

        return swapped;
    }

    /**
     * @notice Add liquidity to Sushiswap pools with ETH/ERC20 Tokens
     */
    function zapIn(
        I1inchAggregationRouterV4 self,
        SwapParams calldata _toPairTokens,
        address _pairAddress,
        uint256 _token0Amount,
        uint256 _token1Amount,
        uint256 _minPairTokens
    )
        public
        returns (uint256)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(_pairAddress);

        address[2] memory tokens = [pair.token0(), pair.token1()];

        // Validate sources
        if (_toPairTokens.desc.srcToken != tokens[0] && _toPairTokens.desc.srcToken != tokens[1]) {
            revert INVALID_SOURCE_TOKEN();
        }

        // Validate dest
        if (_toPairTokens.desc.dstToken != tokens[0] && _toPairTokens.desc.dstToken != tokens[1]) {
            revert INVALID_DEST_TOKEN();
        }

        perform1InchSwap(self, _toPairTokens);

        uint256 lpBought = uniDeposit(pair.token0(), pair.token1(), _token0Amount, _token1Amount);

        if (lpBought < _minPairTokens) {
            revert HIGH_SLIPPAGE();
        }

        emit Zap(msg.sender, _pairAddress, ZapType.ZAP_IN, lpBought);

        return lpBought;
    }

    function zapInFrom2Crv(
        I1inchAggregationRouterV4 self,
        SwapParams calldata _swapFromStable,
        SwapParams calldata _toPairTokens,
        address _pairAddress,
        uint256 _starting2crv,
        uint256 _token0Amount,
        uint256 _token1Amount,
        uint256 _minPairTokens,
        address _intermediateToken
    )
        public
        returns (uint256)
    {
        // The intermediate token should be one of the stable coins on `2Crv`
        if (_intermediateToken != crv2.coins(0) && _intermediateToken != crv2.coins(1)) {
            revert INVALID_INTERMEDIATE_TOKEN();
        }

        // Swaps 2crv for stable using 2crv contract
        crv2.swap2CrvForStable(_intermediateToken, _starting2crv, _swapFromStable.desc.amount);

        // Perform zapIn intermediate with the stable received
        return zapInIntermediate(
            self, _swapFromStable, _toPairTokens, _pairAddress, _token0Amount, _token1Amount, _minPairTokens
        );
    }

    /**
     * @notice Removes liquidity from Sushiswap pools and swaps pair tokens to `_tokenOut`.
     */
    function zapOutToOneTokenFromPair(
        I1inchAggregationRouterV4 self,
        address _pair,
        uint256 _amount,
        uint256 _token0PairAmount,
        uint256 _token1PairAmount,
        SwapParams calldata _tokenSwap
    )
        public
        returns (uint256 tokenOutAmount)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(_pair);

        // Remove liquidity from pair
        _removeLiquidity(pair, _amount, _token0PairAmount, _token1PairAmount);

        // Swap anyone of the tokens to the other
        tokenOutAmount = perform1InchSwap(self, _tokenSwap);

        emit Zap(msg.sender, _pair, ZapType.ZAP_OUT, tokenOutAmount);
    }

    /**
     * @notice Removes liquidity from Sushiswap pools and swaps pair tokens to `_tokenOut`.
     */
    function zapOutAnyToken(
        I1inchAggregationRouterV4 self,
        address _pair,
        uint256 _amount,
        uint256 _token0PairAmount,
        uint256 _token1PairAmount,
        SwapParams calldata _token0Swap,
        SwapParams calldata _token1Swap
    )
        public
        returns (uint256 tokenOutAmount)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(_pair);

        // Remove liquidity from pair
        _removeLiquidity(pair, _amount, _token0PairAmount, _token1PairAmount);

        // Swap token0 to output
        uint256 token0SwappedAmount = perform1InchSwap(self, _token0Swap);

        // Swap token1 to output
        uint256 token1SwappedAmount = perform1InchSwap(self, _token1Swap);

        tokenOutAmount = token0SwappedAmount + token1SwappedAmount;
        emit Zap(msg.sender, _pair, ZapType.ZAP_OUT, tokenOutAmount);
    }

    function zapOutTo2crv(
        I1inchAggregationRouterV4 self,
        address _pair,
        uint256 _amount,
        uint256 _token0PairAmount,
        uint256 _token1PairAmount,
        uint256 _min2CrvAmount,
        address _intermediateToken,
        SwapParams calldata _token0Swap,
        SwapParams calldata _token1Swap
    )
        public
        returns (uint256)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(_pair);

        address[2] memory pairTokens = [IUniswapV2Pair(_pair).token0(), IUniswapV2Pair(_pair).token1()];

        // Check source tokens
        if (_token0Swap.desc.srcToken != pairTokens[0] || _token1Swap.desc.srcToken != pairTokens[1]) {
            revert INVALID_SOURCE_TOKEN();
        }

        if (_token0Swap.desc.dstToken != _intermediateToken || _token1Swap.desc.dstToken != _intermediateToken) {
            revert INVALID_DEST_TOKEN();
        }

        if (_intermediateToken != crv2.coins(0) && _intermediateToken != crv2.coins(1)) {
            revert INVALID_INTERMEDIATE_TOKEN();
        }

        // Remove liquidity from pair
        _removeLiquidity(pair, _amount, _token0PairAmount, _token1PairAmount);

        uint256 stableAmount = perform1InchSwap(self, _token0Swap) + perform1InchSwap(self, _token1Swap);

        // Swap to 2crv
        IERC20(_intermediateToken).approve(address(crv2), stableAmount);

        return crv2.swapStableFor2Crv(_token0Swap.desc.dstToken, stableAmount, _min2CrvAmount);
    }

    function perform1InchSwap(I1inchAggregationRouterV4 self, SwapParams calldata _swap) public returns (uint256) {
        IERC20(_swap.desc.srcToken).safeApprove(address(self), _swap.desc.amount);
        (uint256 returnAmount,) = self.swap(_swap.caller, _swap.desc, _swap.data);
        IERC20(_swap.desc.srcToken).safeApprove(address(self), 0);

        return returnAmount;
    }

    /**
     * Removes liquidity from Sushi.
     */
    function _removeLiquidity(IUniswapV2Pair _pair, uint256 _amount, uint256 _minToken0Amount, uint256 _minToken1Amount)
        private
        returns (uint256 amountA, uint256 amountB)
    {
        _approveToken(address(_pair), address(sushiSwapRouter), _amount);
        return sushiSwapRouter.removeLiquidity(
            _pair.token0(), _pair.token1(), _amount, _minToken0Amount, _minToken1Amount, address(this), deadline
        );
    }

    /**
     * Adds liquidity to Sushi.
     */
    function uniDeposit(address _tokenA, address _tokenB, uint256 _amountADesired, uint256 _amountBDesired)
        public
        returns (uint256)
    {
        _approveToken(_tokenA, address(sushiSwapRouter), _amountADesired);
        _approveToken(_tokenB, address(sushiSwapRouter), _amountBDesired);

        (,, uint256 lp) = sushiSwapRouter.addLiquidity(
            _tokenA,
            _tokenB,
            _amountADesired,
            _amountBDesired,
            1, // amountAMin - no need to worry about front-running since we handle that in main Zap
            1, // amountBMin - no need to worry about front-running since we handle that in main Zap
            address(this), // to
            deadline // deadline
        );

        return lp;
    }

    function _approveToken(address _token, address _spender) internal {
        IERC20 token = IERC20(_token);
        if (token.allowance(address(this), _spender) > 0) {
            return;
        } else {
            token.safeApprove(_spender, type(uint256).max);
        }
    }

    function _approveToken(address _token, address _spender, uint256 _amount) internal {
        IERC20(_token).safeApprove(_spender, 0);
        IERC20(_token).safeApprove(_spender, _amount);
    }

    /* ========== EVENTS ========== */
    /**
     * Emits when zapping in/out.
     * @param _sender sender performing zap action.
     * @param _pool address of the pool pair.
     * @param _type type of action (ie zap in or out).
     * @param _amount output amount after zap (pair amount for Zap In, output token amount for Zap Out)
     */
    event Zap(address indexed _sender, address indexed _pool, ZapType _type, uint256 _amount);

    /* ========== ERRORS ========== */
    error ERROR_SWAPPING_TOKENS();
    error ADDRESS_IS_ZERO();
    error HIGH_SLIPPAGE();
    error INVALID_INTERMEDIATE_TOKEN();
    error INVALID_SOURCE_TOKEN();
    error INVALID_DEST_TOKEN();
    error NON_EXISTANCE_PAIR();
}

