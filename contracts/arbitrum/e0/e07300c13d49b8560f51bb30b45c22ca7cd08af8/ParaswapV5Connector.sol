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
import "./Address.sol";

import "./ERC20Helpers.sol";

import "./IParaswapV5Augustus.sol";

/**
 * @title ParaswapV5Connector
 * @dev Interfaces with Paraswap V5 to swap tokens
 */
contract ParaswapV5Connector {
    // Reference to Paraswap V5 Augustus swapper
    IParaswapV5Augustus private immutable paraswapV5Augustus;

    /**
     * @dev Initializes the ParaswapV5Connector contract
     * @param _paraswapV5Augustus Paraswap V5 augusts reference
     */
    constructor(address _paraswapV5Augustus) {
        paraswapV5Augustus = IParaswapV5Augustus(_paraswapV5Augustus);
    }

    /**
     * @dev Internal function to swap two tokens through Paraswap V5
     * @param tokenIn Token being sent
     * @param tokenOut Token being received
     * @param amountIn Amount of tokenIn being swapped
     * @param minAmountOut Minimum amount of tokenOut willing to receive
     * @param data Calldata to be sent to the Augusuts swapper
     */
    function _swapParaswapV5(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        bytes memory data
    ) internal returns (uint256 amountOut) {
        uint256 preBalanceOut = IERC20(tokenOut).balanceOf(address(this));

        address tokenTransferProxy = paraswapV5Augustus.getTokenTransferProxy();
        ERC20Helpers.approve(tokenIn, tokenTransferProxy, amountIn);
        Address.functionCall(address(paraswapV5Augustus), data, 'PARASWAP_V5_SWAP_FAILED');

        uint256 postBalanceOut = IERC20(tokenOut).balanceOf(address(this));
        amountOut = postBalanceOut - preBalanceOut;
        require(amountOut >= minAmountOut, 'PARASWAP_V5_MIN_AMOUNT');
    }
}

