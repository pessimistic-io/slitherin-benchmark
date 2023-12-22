/**
 * SPDX-License-Identifier: Proprietary
 * 
 * Strateg Protocol contract
 * PROPRIETARY SOFTWARE AND LICENSE. 
 * This contract is the valuable and proprietary property of Strateg Development Association. 
 * Strateg Development Association shall retain exclusive title to this property, and all modifications, 
 * implementations, derivative works, upgrades, productizations and subsequent releases. 
 * To the extent that developers in any way contributes to the further development of Strateg protocol contracts, 
 * developers hereby irrevocably assign and/or agrees to assign all rights in any such contributions or further developments to Strateg Development Association. 
 * Without limitation, Strateg Development Association acknowledges and agrees that all patent rights, 
 * copyrights in and to the Strateg protocol contracts shall remain the exclusive property of Strateg Development Association at all times.
 * 
 * DEVELOPERS SHALL NOT, IN WHOLE OR IN PART, AT ANY TIME: 
 * (i) SELL, ASSIGN, LEASE, DISTRIBUTE, OR OTHER WISE TRANSFER THE STRATEG PROTOCOL CONTRACTS TO ANY THIRD PARTY; 
 * (ii) COPY OR REPRODUCE THE STRATEG PROTOCOL CONTRACTS IN ANY MANNER;
 */
pragma solidity ^0.8.15;

import {IStrategSwapRouter} from "./IStrategSwapRouter.sol";
import {IUniswapV2Router02} from "./IUniswapV2Router02.sol";
import "./IERC20.sol";

contract StrategSwapRouterUniswapV2 is IStrategSwapRouter {

    struct Parameters {
        address router;
        uint amountIn;
        uint amountOutMin;
        address[] path;
        uint deadline;
    }
    
    event Swap(address indexed tokenIn, address indexed tokenOut, uint256 tokenInAmount, uint256 tokenOutAmount);

    constructor() {
    }

    function swap(bytes calldata _parameters) external {
        Parameters memory parameters = abi.decode(_parameters, (Parameters));

        IERC20(parameters.path[0]).approve(address(parameters.router), parameters.amountIn);

        IUniswapV2Router02(parameters.router).swapExactTokensForTokens(
            parameters.amountIn,
            parameters.amountOutMin,
            parameters.path,
            address(this),
            parameters.deadline
        );
    }
}

