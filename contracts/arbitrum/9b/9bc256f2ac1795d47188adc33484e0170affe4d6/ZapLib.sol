// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "./IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {SushiAdapter} from "./SushiAdapter.sol";
import {Babylonian} from "./Babylonian.sol";

library ZapLib {
    using SafeERC20 for IERC20;
    using SushiAdapter for IUniswapV2Router02;

    enum ZapType {
        ZAP_IN,
        ZAP_OUT
    }

    IUniswapV2Factory public constant sushiSwapFactoryAddress =
        IUniswapV2Factory(0xc35DADB65012eC5796536bD9864eD8773aBc74C4);

    IUniswapV2Router02 public constant sushiSwapRouter = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    address public constant wethTokenAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    uint256 private constant deadline = 0xf000000000000000000000000000000000000000000000000000000000000000;

    /**
     * @notice Add liquidity to Sushiswap pools with ETH/ERC20 Tokens
     * @param _fromToken The ERC20 token used
     * @param _pair The Sushiswap pair address
     * @param _amount The amount of fromToken to invest
     * @param _minPoolTokens Minimum quantity of pool tokens to receive. Reverts otherwise
     * @param _intermediateToken intermediate token to swap to (must be one of the tokens in `_pair`) if `_fromToken` is not part of a pair token. Can be zero address if swap is not necessary.
     * @return Amount of LP bought
     */
    function ZapIn(
        address _fromToken,
        address _pair,
        uint256 _amount,
        uint256 _minPoolTokens,
        address _intermediateToken
    )
        external
        returns (uint256)
    {
        _checkZeroAddress(_fromToken);
        _checkZeroAddress(_pair);

        uint256 lpBought = _performZapIn(_fromToken, _pair, _amount, _intermediateToken);

        if (lpBought < _minPoolTokens) {
            revert HIGH_SLIPPAGE();
        }

        emit Zap(msg.sender, _pair, ZapType.ZAP_IN, lpBought);

        return lpBought;
    }

    /**
     * @notice Removes liquidity from Sushiswap pools and swaps pair tokens to `_tokenOut`.
     * @param _pair The pair token to remove liquidity from
     * @param _tokenOut The ERC20 token to zap out to
     * @param _amount The amount of liquidity to remove
     * @param _minOut Minimum amount of `_tokenOut` whne zapping out
     * @return _tokenOutAmount Amount of zap out token
     */
    function ZapOut(address _pair, address _tokenOut, uint256 _amount, uint256 _minOut)
        public
        returns (uint256 _tokenOutAmount)
    {
        _checkZeroAddress(_tokenOut);
        _checkZeroAddress(_pair);

        _tokenOutAmount = _performZapOut(_pair, _tokenOut, _amount);

        if (_tokenOutAmount < _minOut) {
            revert HIGH_SLIPPAGE();
        }

        emit Zap(msg.sender, _pair, ZapType.ZAP_IN, _tokenOutAmount);
    }

    /**
     * @notice Quotes zap in amount for adding liquidity pair from `_inputToken`.
     * @param _inputToken The input token used for zapping in
     * @param _pairAddress The pair address to add liquidity to
     * @param _amount The amount of liquidity to calculate output
     * @param _intermediateToken Intermidate token that will be swapped out
     *
     * Returns estimation of amount of pair tokens that will be available when zapping in.
     */
    function quoteZapIn(address _inputToken, address _pairAddress, uint256 _amount, address _intermediateToken)
        public
        view
        returns (uint256)
    {
        // This function has 4 steps:
        // 1. Set intermediate token
        // 2. Calculate intermediate token amount: `_amount` if swap isn't required, otherwise calculate swap output from swapping `_inputToken` to `_intermediateToken`.
        // 3. Get amountA and amountB quote for swapping `_intermediateToken` to `_pairAddress` pair
        // 4. Get quote for liquidity

        uint256 intermediateAmt;
        address intermediateToken;
        (address _tokenA, address _tokenB) = _getPairTokens(_pairAddress);

        // 1. Set intermediate token
        if (_inputToken != _tokenA && _inputToken != _tokenB) {
            _validateIntermediateToken(_intermediateToken, _tokenA, _tokenB);

            // swap is required:
            // 2. Calculate intermediate token amount: `_amount` if swap isn't required, otherwise calculate swap output from swapping `_inputToken` to `_intermediateToken`.
            address[] memory path = _getSushiPath(_inputToken, _intermediateToken);
            intermediateAmt = sushiSwapRouter.getAmountsOut(_amount, path)[path.length - 1];
            intermediateToken = _intermediateToken;
        } else {
            intermediateToken = _inputToken;
            intermediateAmt = _amount;
        }

        // 3. Get amountA and amountB quote for swapping `_intermediateToken` to `_pairAddress` pair
        (uint256 tokenABought, uint256 tokenBBought) =
            _quoteSwapIntermediate(intermediateToken, _tokenA, _tokenB, intermediateAmt);

        // 4. Get quote for liquidity
        return _quoteLiquidity(_tokenA, _tokenB, tokenABought, tokenBBought);
    }

    /**
     * @notice Quotes zap out amount for removing liquidity `_pair`.
     * @param _pair The address of the pair to remove liquidity from.
     * @param _tokenOut The address of the output token to calculate zap out.
     * @param _amount Amount of liquidity to calculate zap out.
     *
     * Returns the estimation of amount of `_tokenOut` that will be available when zapping out.
     */
    function quoteZapOut(address _pair, address _tokenOut, uint256 _amount) public view returns (uint256) {
        (address tokenA, address tokenB) = _getPairTokens(_pair);

        // estimate amounts out from removing liquidity
        (uint256 amountA, uint256 amountB) = _quoteRemoveLiquidity(_pair, _amount);

        uint256 tokenOutAmount = 0;

        // Calculate swap amount from liquidity pair tokenA to token out.
        if (tokenA != _tokenOut) {
            tokenOutAmount += _calculateSwapOut(tokenA, _tokenOut, amountA);
        } else {
            tokenOutAmount += amountA;
        }

        // Calculate swap amount from liquidity pair tokenB to token out.
        if (tokenB != _tokenOut) {
            tokenOutAmount += _calculateSwapOut(tokenB, _tokenOut, amountB);
        } else {
            tokenOutAmount += amountB;
        }
        return tokenOutAmount;
    }

    /**
     * Validates `_intermediateToken` to ensure that it is not address 0 and is equal to one of the token pairs `_tokenA` or `_tokenB`.
     *
     * Note reverts if pair was not found.
     */
    function _validateIntermediateToken(address _intermediateToken, address _tokenA, address _tokenB) private pure {
        if (_intermediateToken == address(0) || (_intermediateToken != _tokenA && _intermediateToken != _tokenB)) {
            revert INVALID_INTERMEDIATE_TOKEN();
        }
    }

    /**
     * 1. Swaps `_fromToken` to `_intermediateToken` (if necessary)
     * 2. Swaps portion of `_intermediateToken` to the other token pair.
     * 3. Adds liquidity to pair on SushiSwap.
     */
    function _performZapIn(address _fromToken, address _pairAddress, uint256 _amount, address _intermediateToken)
        internal
        returns (uint256)
    {
        uint256 intermediateAmt;
        address intermediateToken;
        (address tokenA, address tokenB) = _getPairTokens(_pairAddress);

        if (_fromToken != tokenA && _fromToken != tokenB) {
            // swap to intermediate
            _validateIntermediateToken(_intermediateToken, tokenA, tokenB);
            intermediateAmt = _token2Token(_fromToken, _intermediateToken, _amount);
            intermediateToken = _intermediateToken;
        } else {
            intermediateToken = _fromToken;
            intermediateAmt = _amount;
        }

        // divide intermediate into appropriate amount to add liquidity
        (uint256 tokenABought, uint256 tokenBBought) =
            _swapIntermediate(intermediateToken, tokenA, tokenB, intermediateAmt);

        return _uniDeposit(tokenA, tokenB, tokenABought, tokenBBought);
    }

    /**
     * 1. Removes `_pair` liquidity from SushiSwap.
     * 2. Swaps liquidity pair tokens to `_tokenOut`.
     */
    function _performZapOut(address _pair, address _tokenOut, uint256 _amount) private returns (uint256) {
        (address tokenA, address tokenB) = _getPairTokens(_pair);
        (uint256 amountA, uint256 amountB) = _removeLiquidity(_pair, tokenA, tokenB, _amount);

        uint256 tokenOutAmount = 0;

        // Swaps token A from liq pair for output token
        if (tokenA != _tokenOut) {
            tokenOutAmount += _token2Token(tokenA, _tokenOut, amountA);
        } else {
            tokenOutAmount += amountA;
        }

        // Swaps token B from liq pair for output token
        if (tokenB != _tokenOut) {
            tokenOutAmount += _token2Token(tokenB, _tokenOut, amountB);
        } else {
            tokenOutAmount += amountB;
        }

        return tokenOutAmount;
    }

    /**
     * Returns the min of the two input numbers.
     */
    function _min(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a < _b ? _a : _b;
    }

    /**
     * Simulates adding liquidity to `_tokenA`/`_tokenB` pair on SushiSwap.
     *
     * Logic is derived from `_addLiquidity` (`UniswapV2Router02.sol`) and `mint` (`UniswapV2Pair.sol`)
     * to simulate addition of liquidity.
     */
    function _quoteLiquidity(address _tokenA, address _tokenB, uint256 _amountADesired, uint256 _amountBDesired)
        internal
        view
        returns (uint256)
    {
        uint256 amountA;
        uint256 amountB;
        IUniswapV2Pair pair = _getPair(_tokenA, _tokenB);
        (uint256 reserveA, uint256 reserveB,) = pair.getReserves();
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (_amountADesired, _amountBDesired);
        } else {
            uint256 amountBOptimal = sushiSwapRouter.quote(_amountADesired, reserveA, reserveB);
            if (amountBOptimal <= _amountBDesired) {
                (amountA, amountB) = (_amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = sushiSwapRouter.quote(_amountBDesired, reserveB, reserveA);
                (amountA, amountB) = (amountAOptimal, _amountBDesired);
            }
        }

        return _min((amountA * pair.totalSupply()) / reserveA, (amountB * pair.totalSupply()) / reserveB);
    }

    /**
     * Simulates removing liquidity from `_pair` for `_amount` on SushiSwap.
     */
    function _quoteRemoveLiquidity(address _pair, uint256 _amount)
        private
        view
        returns (uint256 _amountA, uint256 _amountB)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(_pair);
        address tokenA = pair.token0();
        address tokenB = pair.token1();
        uint256 balance0 = IERC20(tokenA).balanceOf(_pair);
        uint256 balance1 = IERC20(tokenB).balanceOf(_pair);

        uint256 _totalSupply = pair.totalSupply();
        _amountA = (_amount * balance0) / _totalSupply;
        _amountB = (_amount * balance1) / _totalSupply;
    }

    /**
     * Returns the addresses of Sushi pair tokens for the given `_pairAddress`.
     */
    function _getPairTokens(address _pairAddress) private view returns (address, address) {
        IUniswapV2Pair uniPair = IUniswapV2Pair(_pairAddress);
        return (uniPair.token0(), uniPair.token1());
    }

    /**
     * Helper that returns the Sushi pair address for the given pair tokens `_tokenA` and `_tokenB`.
     */
    function _getPair(address _tokenA, address _tokenB) private view returns (IUniswapV2Pair) {
        IUniswapV2Pair pair = IUniswapV2Pair(sushiSwapFactoryAddress.getPair(_tokenA, _tokenB));
        if (address(pair) == address(0)) {
            revert NON_EXISTANCE_PAIR();
        }
        return pair;
    }

    /**
     * Removes liquidity from Sushi.
     */
    function _removeLiquidity(address _pair, address _tokenA, address _tokenB, uint256 _amount)
        private
        returns (uint256 amountA, uint256 amountB)
    {
        _approveToken(_pair, address(sushiSwapRouter), _amount);
        return sushiSwapRouter.removeLiquidity(_tokenA, _tokenB, _amount, 1, 1, address(this), deadline);
    }

    /**
     * Adds liquidity to Sushi.
     */
    function _uniDeposit(address _tokenA, address _tokenB, uint256 _amountADesired, uint256 _amountBDesired)
        private
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

    /**
     * Swaps `_inputToken` to pair tokens `_tokenPairA`/`_tokenPairB` for the `_amount`.
     * @return _amountA the amount of `_tokenPairA` bought.
     * @return _amountB the amount of `_tokenPairB` bought.
     */
    function _swapIntermediate(address _inputToken, address _tokenPairA, address _tokenPairB, uint256 _amount)
        internal
        returns (uint256 _amountA, uint256 _amountB)
    {
        IUniswapV2Pair pair = _getPair(_tokenPairA, _tokenPairB);
        (uint256 resA, uint256 resB,) = pair.getReserves();
        if (_inputToken == _tokenPairA) {
            uint256 amountToSwap = _calculateSwapInAmount(resA, _amount);
            //if no reserve or a new pair is created
            if (amountToSwap <= 0) {
                amountToSwap = _amount / 2;
            }
            _amountB = _token2Token(_inputToken, _tokenPairB, amountToSwap);
            _amountA = _amount - amountToSwap;
        } else {
            uint256 amountToSwap = _calculateSwapInAmount(resB, _amount);
            //if no reserve or a new pair is created
            if (amountToSwap <= 0) {
                amountToSwap = _amount / 2;
            }
            _amountA = _token2Token(_inputToken, _tokenPairA, amountToSwap);
            _amountB = _amount - amountToSwap;
        }
    }

    /**
     * Simulates swap of `_inputToken` to pair tokens `_tokenPairA`/`_tokenPairB` for the `_amount`.
     * @return _amountA quote amount of `_tokenPairA`
     * @return _amountB quote amount of `_tokenPairB`
     */
    function _quoteSwapIntermediate(address _inputToken, address _tokenPairA, address _tokenPairB, uint256 _amount)
        internal
        view
        returns (uint256 _amountA, uint256 _amountB)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(sushiSwapFactoryAddress.getPair(_tokenPairA, _tokenPairB));
        (uint256 resA, uint256 resB,) = pair.getReserves();

        if (_inputToken == _tokenPairA) {
            uint256 amountToSwap = _calculateSwapInAmount(resA, _amount);
            //if no reserve or a new pair is created
            if (amountToSwap <= 0) {
                amountToSwap = _amount / 2;
            }
            _amountB = _calculateSwapOut(_inputToken, _tokenPairB, amountToSwap);
            _amountA = _amount - amountToSwap;
        } else {
            uint256 amountToSwap = _calculateSwapInAmount(resB, _amount);
            //if no reserve or a new pair is created
            if (amountToSwap <= 0) {
                amountToSwap = _amount / 2;
            }
            _amountA = _calculateSwapOut(_inputToken, _tokenPairA, amountToSwap);
            _amountB = _amount - amountToSwap;
        }
    }

    /**
     * Calculates the amounts out from swapping `_tokenA` to `_tokenB` for the given `_amount`.
     */
    function _calculateSwapOut(address _tokenA, address _tokenB, uint256 _amount)
        private
        view
        returns (uint256 _amountOut)
    {
        address[] memory path = _getSushiPath(_tokenA, _tokenB);
        // `getAmountsOut` will return same size array as path, and we only care about the
        // last element which will give us the swap out amount we are looking for
        uint256[] memory amountsOut = sushiSwapRouter.getAmountsOut(_amount, path);
        return amountsOut[path.length - 1];
    }

    /**
     * Helper that reverts if `_addr` is zero.
     */
    function _checkZeroAddress(address _addr) private pure {
        if (_addr == address(0)) {
            revert ADDRESS_IS_ZERO();
        }
    }

    /**
     * Returns the appropriate swap path for Sushi swap.
     */
    function _getSushiPath(address _fromToken, address _toToken) internal pure returns (address[] memory) {
        address[] memory path;
        if (_fromToken == wethTokenAddress || _toToken == wethTokenAddress) {
            path = new address[](2);
            path[0] = _fromToken;
            path[1] = _toToken;
        } else {
            path = new address[](3);
            path[0] = _fromToken;
            path[1] = wethTokenAddress;
            path[2] = _toToken;
        }
        return path;
    }

    /**
     * Computes the amount of intermediate tokens to swap for adding liquidity.
     */
    function _calculateSwapInAmount(uint256 _reserveIn, uint256 _userIn) internal pure returns (uint256) {
        return (Babylonian.sqrt(_reserveIn * ((_userIn * 3988000) + (_reserveIn * 3988009))) - (_reserveIn * 1997)) / 1994;
    }

    /**
     * @notice This function is used to swap ERC20 <> ERC20
     * @param _source The token address to swap from.
     * @param _destination The token address to swap to.
     * @param _amount The amount of tokens to swap
     * @return _tokenBought The quantity of tokens bought
     */
    function _token2Token(address _source, address _destination, uint256 _amount)
        internal
        returns (uint256 _tokenBought)
    {
        if (_source == _destination) {
            return _amount;
        }

        _approveToken(_source, address(sushiSwapRouter), _amount);

        address[] memory path = _getSushiPath(_source, _destination);
        uint256[] memory amountsOut =
            sushiSwapRouter.swapExactTokensForTokens(_amount, 1, path, address(this), deadline);
        _tokenBought = amountsOut[path.length - 1];

        if (_tokenBought == 0) {
            revert ERROR_SWAPPING_TOKENS();
        }
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
    error NON_EXISTANCE_PAIR();
}

