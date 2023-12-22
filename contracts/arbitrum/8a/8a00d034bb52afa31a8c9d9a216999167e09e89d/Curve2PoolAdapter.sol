// SPDX-License-Identifier: UNLICENSED

// Copyright (c) 2023 JonesDAO - All rights reserved
// Jones DAO: https://www.jonesdao.io/

// Check https://docs.jonesdao.io/jones-dao/other/bounty for details on our bounty program.

pragma solidity ^0.8.10;

// Interfaces
import {IStableSwap} from "./IStableSwap.sol";
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import {IERC20} from "./IERC20.sol";

library Curve2PoolAdapter {
    address constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant SUSHI_ROUTER = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;

    IUniswapV2Router02 constant sushiRouter = IUniswapV2Router02(SUSHI_ROUTER);

    /**
     * @notice Swaps a token for 2CRV
     * @param _inputToken The token to swap
     * @param _amount The token amount to swap
     * @param _stableToken The address of the stable token to swap the `_inputToken`
     * @param _minStableAmount The minimum output amount of `_stableToken`
     * @param _min2CrvAmount The minimum output amount of 2CRV to receive
     * @param _recipient The address that's going to receive the 2CRV
     * @return The amount of 2CRV received
     */
    function swapTokenFor2Crv(
        IStableSwap self,
        address _inputToken,
        uint256 _amount,
        address _stableToken,
        uint256 _minStableAmount,
        uint256 _min2CrvAmount,
        address _recipient
    ) public returns (uint256) {
        if (_stableToken != USDC && _stableToken != USDT) {
            revert INVALID_STABLE_TOKEN();
        }

        address[] memory route = _swapTokenFor2CrvRoute(_inputToken, _stableToken);

        uint256[] memory swapOutputs =
            sushiRouter.swapExactTokensForTokens(_amount, _minStableAmount, route, _recipient, block.timestamp);

        uint256 stableOutput = swapOutputs[swapOutputs.length - 1];

        uint256 amountOut = swapStableFor2Crv(self, _stableToken, stableOutput, _min2CrvAmount);

        emit SwapTokenFor2Crv(_amount, amountOut, _inputToken);

        return amountOut;
    }

    /**
     * @notice Swaps 2CRV for `_outputToken`
     * @param _outputToken The output token to receive
     * @param _amount The amount of 2CRV to swap
     * @param _stableToken The address of the stable token to receive
     * @param _minStableAmount The minimum output amount of `_stableToken` to receive
     * @param _minTokenAmount The minimum output amount of `_outputToken` to receive
     * @param _recipient The address that's going to receive the `_outputToken`
     * @return The amount of `_outputToken` received
     */
    function swap2CrvForToken(
        IStableSwap self,
        address _outputToken,
        uint256 _amount,
        address _stableToken,
        uint256 _minStableAmount,
        uint256 _minTokenAmount,
        address _recipient
    ) public returns (uint256) {
        if (_stableToken != USDC && _stableToken != USDT) {
            revert INVALID_STABLE_TOKEN();
        }

        uint256 stableAmount = swap2CrvForStable(self, _stableToken, _amount, _minStableAmount);

        address[] memory route = _swapStableForTokenRoute(_outputToken, _stableToken);

        uint256[] memory swapOutputs =
            sushiRouter.swapExactTokensForTokens(stableAmount, _minTokenAmount, route, _recipient, block.timestamp);

        uint256 amountOut = swapOutputs[swapOutputs.length - 1];

        emit Swap2CrvForToken(_amount, amountOut, _outputToken);

        return amountOut;
    }

    /**
     * @notice Swaps 2CRV for a stable token
     * @param _stableToken The stable token address
     * @param _amount The amount of 2CRV to sell
     * @param _minStableAmount The minimum amount stables to receive
     * @return The amount of stables received
     */
    function swap2CrvForStable(IStableSwap self, address _stableToken, uint256 _amount, uint256 _minStableAmount)
        public
        returns (uint256)
    {
        int128 stableIndex;

        if (_stableToken != USDC && _stableToken != USDT) {
            revert INVALID_STABLE_TOKEN();
        }

        if (_stableToken == USDC) {
            stableIndex = 0;
        }
        if (_stableToken == USDT) {
            stableIndex = 1;
        }

        return self.remove_liquidity_one_coin(_amount, stableIndex, _minStableAmount);
    }

    /**
     * @notice Swaps a stable token for 2CRV
     * @param _stableToken The stable token address
     * @param _amount The amount of `_stableToken` to sell
     * @param _min2CrvAmount The minimum amount of 2CRV to receive
     * @return The amount of 2CRV received
     */
    function swapStableFor2Crv(IStableSwap self, address _stableToken, uint256 _amount, uint256 _min2CrvAmount)
        public
        returns (uint256)
    {
        uint256[2] memory deposits;
        if (_stableToken != USDC && _stableToken != USDT) {
            revert INVALID_STABLE_TOKEN();
        }

        if (_stableToken == USDC) {
            deposits = [_amount, 0];
        }
        if (_stableToken == USDT) {
            deposits = [0, _amount];
        }

        IERC20(_stableToken).approve(address(self), _amount);

        return self.add_liquidity(deposits, _min2CrvAmount);
    }

    /**
     * @notice Get route to swap stable for other token.
     */
    function _swapStableForTokenRoute(address _outputToken, address _stableToken)
        internal
        pure
        returns (address[] memory)
    {
        address[] memory route;
        if (_outputToken == WETH) {
            // handle weth swaps
            route = new address[](2);
            route[0] = _stableToken;
            route[1] = _outputToken;
        } else {
            route = new address[](3);
            route[0] = _stableToken;
            route[1] = WETH;
            route[2] = _outputToken;
        }
        return route;
    }

    /**
     * @notice Get route to swap an asset for 2crv.
     */
    function _swapTokenFor2CrvRoute(address _inputToken, address _stableToken)
        internal
        pure
        returns (address[] memory)
    {
        address[] memory route;
        if (_inputToken == WETH) {
            // handle weth swaps
            route = new address[](2);
            route[0] = _inputToken;
            route[1] = _stableToken;
        } else {
            route = new address[](3);
            route[0] = _inputToken;
            route[1] = WETH;
            route[2] = _stableToken;
        }
        return route;
    }

    event Swap2CrvForToken(uint256 _amountIn, uint256 _amountOut, address _token);
    event SwapTokenFor2Crv(uint256 _amountIn, uint256 _amountOut, address _token);

    error INVALID_STABLE_TOKEN();
}

