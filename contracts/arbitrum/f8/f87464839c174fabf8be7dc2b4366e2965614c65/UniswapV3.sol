//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20 } from "./IERC20.sol";
import { LibAsset } from "./LibAsset.sol";
import { LibUtil } from "./LibUtil.sol";

interface ISwapRouterUniV3 {
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

interface ISwapQuoterUniV3 {
    function quoteExactInput(bytes memory path, uint256 amountIn) external returns (uint256 amountOut);
}

abstract contract UniswapV3 {
    // address constant exchangeQuoter = address(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);

    ///////////////////////////
    ///////// STORAGE  ////////
    ///////////////////////////
    // mapping(uint256 => mapping (address => address)) public routerToQuoteAddress;
    
    // function initializeRouterToQuoteAddress()internal{
    //     routerToQuoteAddress[1][address(0xE592427A0AEce92De3Edee1F18E0157C05861564)]=address(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    //     routerToQuoteAddress[10][address(0xE592427A0AEce92De3Edee1F18E0157C05861564)]=address(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    //     routerToQuoteAddress[42161][address(0xE592427A0AEce92De3Edee1F18E0157C05861564)]=address(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    //     // etc.
    // }

    struct UniswapV3Data {
        bytes path;
        uint256 deadline;
    }

    function swapOnUniswapV3(
        address fromToken,
        uint256 fromAmount,
        address exchange,
        bytes calldata payload
    ) internal returns (uint256 receivedAmount){
        UniswapV3Data memory data = abi.decode(payload, (UniswapV3Data));

        LibAsset.approveERC20(IERC20(fromToken), exchange, fromAmount);

        receivedAmount = ISwapRouterUniV3(exchange).exactInput(
            ISwapRouterUniV3.ExactInputParams({
                path: data.path,
                recipient: address(this),
                deadline: data.deadline,
                amountIn: fromAmount,
                amountOutMinimum: 1
            })
        );
    }

    function quoteOnUniswapV3(
        address,
        uint256 fromAmount,
        address exchange,
        bytes calldata payload
    ) internal returns (uint256 receivedAmount){
        UniswapV3Data memory data = abi.decode(payload, (UniswapV3Data));

        // address exchangeQuoter = routerToQuoteAddress[block.chainid][exchange];
        // if (LibUtil.isZeroAddress(exchangeQuoter)){
        //     revert("Unimplement exchanger");
        // }
        
        // TODO: need to generalize that  
        receivedAmount = ISwapQuoterUniV3(address(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6)).quoteExactInput(
                data.path,
                fromAmount
        );
        return receivedAmount;
    }
}
