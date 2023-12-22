pragma solidity 0.8.9;

/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SharwaFinance
 * Copyright (C) 2023 SharwaFinance
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/

import {TransferHelper} from "./TransferHelper.sol";
import {ISwapRouter} from "./ISwapRouter.sol";
import {ERC20} from "./ERC20.sol";
import {RoleManager, Ownable} from "./RoleManager.sol";
import {IExchanger} from "./IExchanger.sol";
import {IWETH9} from "./IWETH9.sol";

/**
 * @title Exchanger
 * @author 0nika0
 * @dev A smart contract for executing token swaps and managing roles for traders.
 * 
 * This contract allows users with the TRADER_ROLE to perform token swaps and enforces checks on the validity of swaps.
 */
contract Exchanger is Ownable, IExchanger {

    ISwapRouter public swapRouter;
    RoleManager public roleManager;
    IWETH9 public weth9;

    constructor(
        address _swapRouter,
        address _roleManager,
        address _weth9
    ) {
        swapRouter = ISwapRouter(_swapRouter);
        roleManager = RoleManager(_roleManager);
        weth9 = IWETH9(_weth9);
    }

    // EXTERNAL FUNCTIONS // 

    /**
     * @dev See {IExchanger-swap}.
     */
    function swap(bytes memory data, address from, address to) external payable {
        require(roleManager.hasRole(roleManager.TRADER_ROLE(), msg.sender), "msg.sender not have TRADER_ROLE");
        ExchangeData memory exchangeData = decodeFromExchange(data);

        if (exchangeData.swap) {
            uint256 msgValue;
            uint256 amountOut;

            if (exchangeData.isETH) {
                msgValue = exchangeData.amountIn;
            } else {
                TransferHelper.safeTransferFrom(exchangeData.tokenIn, from, address(this), exchangeData.amountIn);
                TransferHelper.safeApprove(exchangeData.tokenIn, address(swapRouter), exchangeData.amountIn);
            }
            
            if (exchangeData.isETH && exchangeData.tokenIn == exchangeData.tokenOut) {
                weth9.deposit{value: msgValue}();
            } else {
                ISwapRouter.ExactInputParams memory params =
                ISwapRouter.ExactInputParams({
                    path: exchangeData.path,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: exchangeData.amountIn,
                    amountOutMinimum: exchangeData.amountOutMinimum
                });

                amountOut = swapRouter.exactInput{value: msgValue}(params);
                require(amountOut >= exchangeData.amountOutMinimum, "invalid swap");
                ERC20(exchangeData.tokenOut).transfer(from, amountOut - exchangeData.amountOutMinimum);
            }

            ERC20(exchangeData.tokenOut).transfer(to, exchangeData.amountOutMinimum);
            
            if (exchangeData.isETH && address(this).balance != 0) payable(to).transfer(address(this).balance);
        } else {
            ERC20(exchangeData.tokenIn).transferFrom(from, to, exchangeData.amountIn);
        }
    }

    // PURE FUNCTIONS //
    
    /**
     * @dev See {IExchanger-checkMsgValue}.
     */
    function checkMsgValue(bytes[] memory swapDataArray, uint256 msgValue) external pure {
        uint256 msgValueCalc;
        for (uint i = 0; i < swapDataArray.length; i++) {
            ExchangeData memory exchangeData = decodeFromExchange(swapDataArray[i]);
            if (exchangeData.isETH && exchangeData.swap) {
                msgValueCalc += exchangeData.amountIn;
            }
        }
        require(msgValue == msgValueCalc, "invalid msg.value");
    }

    /**
     * @dev See {IExchanger-calculateMsgValue}.
     */
    function calculateMsgValue(bytes memory swapData) external pure returns (uint256 value) {
        ExchangeData memory exchangeData = decodeFromExchange(swapData);
        if (exchangeData.isETH && exchangeData.swap) value = exchangeData.amountIn; 
    }

    /**
     * @dev See {IExchanger-encodeFromExchange}.
     */
    function encodeFromExchange(ExchangeData memory data) external pure returns (bytes memory paramData) {
        return abi.encode(data);
    }

    /**
     * @dev See {IExchanger-decodeFromExchange}.
     */
    function decodeFromExchange(bytes memory paramData) public pure returns (ExchangeData memory data) {
        (
            data
        ) = abi.decode(paramData, (
            ExchangeData
        ));
    }
}
