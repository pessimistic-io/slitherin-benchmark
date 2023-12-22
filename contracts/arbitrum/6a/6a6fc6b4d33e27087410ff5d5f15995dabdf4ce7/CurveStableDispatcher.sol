// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ICurveStableSwap} from "./ICurveStableSwap.sol";
import {ICurveStableDispatcher} from "./ICurveStableDispatcher.sol";
import {IWETH} from "./IWETH.sol";

contract CurveStableDispatcher is ICurveStableDispatcher {
    using SafeERC20 for IERC20;

    address public immutable weth;

    error InsufficientAmountIn();

    constructor(address _weth) {
        weth = _weth;
    }

    /// @notice To receive ETH from WETH
    receive() external payable {}

    function exchange(
        address _pool,
        bool _isNativePool,
        int128 _tokenInIndex,
        int128 _tokenOutIndex,
        address _tokenIn,
        address _tokenOut,
        address _to
    ) external override {
        ICurveStableSwap pool = ICurveStableSwap(_pool);
        IERC20 tokenIn = IERC20(_tokenIn);
        IERC20 tokenOut = IERC20(_tokenOut);
        bool isNativeTokenIn = _tokenIn == weth && _isNativePool;
        bool isNatvieTokenOut = _tokenOut == weth && _isNativePool;
        uint256 amountIn = tokenIn.balanceOf(address(this));
        if (amountIn == 0) revert InsufficientAmountIn();
        if (isNativeTokenIn) {
            IWETH(_tokenIn).withdraw(amountIn); 
            pool.exchange{value: address(this).balance}(
                _tokenInIndex, 
                _tokenOutIndex, 
                address(this).balance, 
                0
            );
        } else {
            tokenIn.safeIncreaseAllowance(address(pool), amountIn);
            pool.exchange(_tokenInIndex, _tokenOutIndex, amountIn, 0);
        }
        if (isNatvieTokenOut) {
            IWETH(_tokenOut).deposit{value: address(this).balance}();
        }
        tokenOut.safeTransfer(_to, tokenOut.balanceOf(address(this)));
    }

    function exchange_underlying(
        address _pool,
        int128 _tokenInIndex,
        int128 _tokenOutIndex,
        address _tokenIn,
        address _tokenOut,
        address _to
    ) external override {
        ICurveStableSwap metaPool = ICurveStableSwap(_pool);
        IERC20 tokenIn = IERC20(_tokenIn);
        IERC20 tokenOut = IERC20(_tokenOut);
        uint256 amountIn = tokenIn.balanceOf(address(this));
        if (amountIn == 0) revert InsufficientAmountIn();
        tokenIn.safeIncreaseAllowance(address(metaPool), amountIn);
        metaPool.exchange_underlying(
            _tokenInIndex,
            _tokenOutIndex,
            amountIn,
            0
        );
        tokenOut.safeTransfer(_to, tokenOut.balanceOf(address(this)));
    }
}

