// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IERC20Metadata.sol";

import "./FixedPoint.sol";

import "./I2CrvPool.sol";

/**
 * @title Curve2CrvConnector
 */
contract Curve2CrvConnector {
    using FixedPoint for uint256;

    /**
     * @dev Adds liquidity to the 2CRV pool
     * @param pool Address of the 2CRV pool to join
     * @param tokenIn Address of the token to join the 2CRV pool
     * @param amountIn Amount of tokens to join the 2CRV pool
     * @param slippage Slippage value to be used to compute the desired min amount out of pool tokens
     */
    function join(address pool, address tokenIn, uint256 amountIn, uint256 slippage) external returns (uint256) {
        if (amountIn == 0) return 0;
        require(slippage <= FixedPoint.ONE, '2CRV_SLIPPAGE_ABOVE_ONE');
        (uint256 tokenIndex, uint256 tokenScale) = _findTokenInfo(pool, tokenIn);

        // Compute min amount out
        uint256 expectedAmountOut = (amountIn * tokenScale).divUp(I2CrvPool(pool).get_virtual_price());
        uint256 minAmountOut = expectedAmountOut.mulUp(FixedPoint.ONE - slippage);

        // Join pool
        uint256 initialPoolTokenBalance = I2CrvPool(pool).balanceOf(address(this));
        IERC20(tokenIn).approve(address(pool), amountIn);
        uint256[2] memory amounts;
        amounts[tokenIndex] = amountIn;
        I2CrvPool(pool).add_liquidity(amounts, minAmountOut);
        uint256 finalPoolTokenBalance = I2CrvPool(pool).balanceOf(address(this));
        return finalPoolTokenBalance - initialPoolTokenBalance;
    }

    /**
     * @dev Removes liquidity from 2CRV pool
     * @param pool Address of the 2CRV pool to exit
     * @param amountIn Amount of pool tokens to exit from the 2CRV pool
     * @param tokenOut Address of the token to exit the pool
     * @param slippage Slippage value to be used to compute the desired min amount out of tokens
     */
    function exit(address pool, uint256 amountIn, address tokenOut, uint256 slippage)
        external
        returns (uint256 amountOut)
    {
        if (amountIn == 0) return 0;
        require(slippage <= FixedPoint.ONE, '2CRV_INVALID_SLIPPAGE');
        (uint256 tokenIndex, uint256 tokenScale) = _findTokenInfo(pool, tokenOut);

        // Compute min amount out
        uint256 expectedAmountOut = amountIn.mulUp(I2CrvPool(pool).get_virtual_price()) / tokenScale;
        uint256 minAmountOut = expectedAmountOut.mulUp(FixedPoint.ONE - slippage);

        // Exit pool
        uint256 initialTokenOutBalance = IERC20(tokenOut).balanceOf(address(this));
        I2CrvPool(pool).remove_liquidity_one_coin(amountIn, int128(int256(tokenIndex)), minAmountOut);
        uint256 finalTokenOutBalance = IERC20(tokenOut).balanceOf(address(this));
        return finalTokenOutBalance - initialTokenOutBalance;
    }

    /**
     * @dev Finds the index and scale factor of a token in the 2CRV pool
     */
    function _findTokenInfo(address pool, address token) internal view returns (uint256 index, uint256 scale) {
        for (uint256 i = 0; true; i++) {
            try I2CrvPool(pool).coins(i) returns (address coin) {
                if (token == coin) {
                    uint256 decimals = IERC20Metadata(token).decimals();
                    require(decimals <= 18, '2CRV_TOKEN_ABOVE_18_DECIMALS');
                    return (i, 10**(18 - decimals));
                }
            } catch {
                revert('2CRV_TOKEN_NOT_FOUND');
            }
        }
        revert('2CRV_TOKEN_NOT_FOUND');
    }
}

