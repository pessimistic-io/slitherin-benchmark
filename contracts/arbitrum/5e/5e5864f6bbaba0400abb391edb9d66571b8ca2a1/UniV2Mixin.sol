// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./IUniswapV2Router02.sol";
import "./ISwapErrors.sol";
import "./Babylonian.sol";

abstract contract UniV2Mixin is ISwapErrors {
    using SafeERC20 for IERC20;

    /// @dev tokenA => (tokenB => (router => path)): returns best path to swap
    ///         tokenA to tokenB for the given router (protocol)
    mapping(address => mapping(address => mapping(address => address[]))) public uniV2SwapPaths;

    /// @dev Helper function to swap {_from} to {_to} given an {_amount}.
    function _swapUniV2(address _from, address _to, uint256 _amount, uint256 _minAmountOut, address _router)
        internal
        returns (uint256 amountOut)
    {
        if (_from == _to || _amount == 0) {
            return 0;
        }
        address[] storage path = uniV2SwapPaths[_from][_to][_router];
        require(path.length >= 2, "Missing path for swap");

        uint256 predictedOutput = _getAmountOut(_amount, path, _router);
        if (predictedOutput == 0) {
            emit GetAmountsOutFailed(_router, _amount, _from, _to);
            return 0;
        }

        uint256 toBalBefore = IERC20(_to).balanceOf(address(this));
        IERC20(_from).safeIncreaseAllowance(_router, _amount);
        try IUniswapV2Router02(_router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
            _amount, _minAmountOut, path, address(this), block.timestamp
        ) {
            amountOut = IERC20(_to).balanceOf(address(this)) - toBalBefore;
        } catch {
            emit SwapFailed(_router, _amount, _minAmountOut, _from, _to);
        }
    }

    /// @dev Helper function to get the predicted output of a swap given an {_amount}, {_path} and {_router}
    function _getAmountOut(uint256 _amount, address[] storage _path, address _router)
        private
        view
        returns (uint256 amountOut)
    {
        try IUniswapV2Router02(_router).getAmountsOut(_amount, _path) returns (uint256[] memory amounts) {
            amountOut = amounts[_path.length - 1];
        } catch {
            amountOut = 0;
        }
    }

    /**
     * @dev Core harvest function. Adds more liquidity using {lpToken0} and {lpToken1}.
     */
    function _addLiquidityUniV2(address _lpToken0, address _lpToken1, address _router) internal {
        uint256 lp0Bal = IERC20(_lpToken0).balanceOf(address(this));
        uint256 lp1Bal = IERC20(_lpToken1).balanceOf(address(this));

        if (lp0Bal != 0 && lp1Bal != 0) {
            IERC20(_lpToken0).safeIncreaseAllowance(_router, lp0Bal);
            IERC20(_lpToken1).safeIncreaseAllowance(_router, lp1Bal);
            IUniswapV2Router02(_router).addLiquidity(
                _lpToken0, _lpToken1, lp0Bal, lp1Bal, 0, 0, address(this), block.timestamp
            );
        }
    }

    function _getSwapAmountUniV2(uint256 _investmentA, uint256 _reserveA, uint256 _reserveB, address _router)
        internal
        pure
        returns (uint256 swapAmount)
    {
        uint256 halfInvestment = _investmentA / 2;
        uint256 nominator = IUniswapV2Router02(_router).getAmountOut(halfInvestment, _reserveA, _reserveB);
        uint256 denominator =
            IUniswapV2Router02(_router).quote(halfInvestment, _reserveA + halfInvestment, _reserveB - nominator);
        swapAmount = _investmentA - (Babylonian.sqrt(halfInvestment * halfInvestment * nominator / denominator));
    }

    /// @dev Update {SwapPath} for a specified pair of tokens.
    function _updateUniV2SwapPath(address _tokenIn, address _tokenOut, address _router, address[] calldata _path)
        internal
    {
        require(
            _tokenIn != _tokenOut && _path.length >= 2 && _path[0] == _tokenIn && _path[_path.length - 1] == _tokenOut
        );
        uniV2SwapPaths[_tokenIn][_tokenOut][_router] = _path;
    }

    // Be sure to permission this in implementation
    function updateUniV2SwapPath(address _tokenIn, address _tokenOut, address _router, address[] calldata _path)
        external
        virtual;
}

