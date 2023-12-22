// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;


//import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import "./IUniswapV2Router01.sol";
//import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

//import '@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol';
import "./IUniswapV2Pair.sol";
import "./ISwapRouter.sol";
//import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';

import "./IFlashLoanRecipient.sol";
import "./IVault.sol";

import "./TimeLock.sol";

//import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
//import {OwnerIsCreator} from "@chainlink/contracts-ccip/src/v0.8/shared/access/OwnerIsCreator.sol";
//import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
//import {IERC20} from "@chainlink/contracts-ccip/src/v0.8/vendor/openzeppelin-solidity/v4.8.0/token/ERC20/IERC20.sol";
//import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";


//import '@uniswap/lib/contracts/libraries/Babylonian.sol';

//import '../libraries/UniswapV2Library.sol';



contract FlashLoanSwapper_1 is TimeLock {

    address token1;
    address token2;
    address DEXROUTER;

    constructor(
    address _token1,
    address _token2,
    address _DEXROUTER
    )
    {
        token2 = _token2;
        DEXROUTER = _DEXROUTER;
        token1 = _token1;
    }


    address vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    IUniswapV2Router01 QSrouter;
    // For the scope of these swap examples,
    // we will detail the design considerations when using `exactInput`, `exactInputSingle`, `exactOutput`, and  `exactOutputSingle`.
    // It should be noted that for the sake of these examples we pass in the swap router as a constructor argument instead of inheriting it.
    // More advanced example contracts will detail how to inherit the swap router safely.
    // This example swaps DAI/WETH9 for single path swaps and DAI/USDC/WETH9 for multi path swaps.



    // Tiered fees (from 0.05%), which would favour stabler coins (USDC,..)
    uint24 public constant UniswapPoolFee = 300;
    /// @notice swapExactInputSingle swaps a fixed amount of DAI for a maximum possible amount of WETH9
    /// using the DAI/WETH9 0.3% pool by calling `exactInputSingle` in the swap router.
    /// @dev The calling address must approve this contract to spend at least `amountIn` worth of its DAI for this function to succeed.
    /// @param amountIn The exact amount of DAI that will be swapped for WETH9.
    /// @return amountOut The amount of WETH9 received.
    function swapExactInputSingle(address tokenEins, address router, uint256 amountIn) external returns (uint256 amountOut) {
// msg.sender must approve this contract

// Transfer the specified amount of DAI to this contract.

        // Approve the router to spend DAI.
        IERC20(tokenEins).approve(router,amountIn);
        ISwapRouter swapRouter = ISwapRouter(router);
        amountOut = swapRouter.exactInputSingle(
           ISwapRouter.ExactInputSingleParams({
              tokenIn: tokenEins,
              tokenOut: token2,
              fee: UniswapPoolFee,
              recipient: address(this),
              deadline: block.timestamp,
              amountIn: amountIn,
              amountOutMinimum: 0,
              sqrtPriceLimitX96: 0
         }));

        // The call to `exactInputSingle` executes the swap.
        //amountOut = swapRouter.exactInputSingle(params);
    }


    function swapQuickSwap(address tokenEins, address router, uint256 amountIn) external returns (uint256 amountOut)
    {

        IERC20(token1).approve(router,amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenEins;
        path[1] = token2;

        address to = address(this);

        QSrouter.swapExactTokensForTokens(
            amountIn,
            0, // amountOutMin: we can skip computing this number because the math is tested
            path,
            to,
            block.timestamp+60
        );

    }



    function receiveFlashLoan(
          IERC20[] memory tokens,
          uint256[] memory amounts,
          uint256[] memory feeAmounts,
          bytes memory
          ) external {
            for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            uint256 amount = amounts[i];
//            console.log("borrowed amount:", amount);
            uint256 feeAmount = feeAmounts[i];
//            console.log("flashloan fee: ", feeAmount);

            if (DEXROUTER==0xE592427A0AEce92De3Edee1F18E0157C05861564) {
                this.swapExactInputSingle(token1,DEXROUTER,amount);
            }

            if (DEXROUTER==0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff) {
                this.swapQuickSwap(token1,DEXROUTER,amount);
            }


            IERC20(token2).transfer(msg.sender,IERC20(token2).balanceOf(address(this)));


            // wait

            // Sono tornati nel contratto USDC, e di piu'..

            this.execute(vault,amount,"","",block.timestamp + 11);

            }
    }


    function flashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
        ) external payable {

        // Nel dettaglio questa funzione esegue receiveFlashLoan hook
        IVault(vault).flashLoan(
        IFlashLoanRecipient(address(this)),
        tokens,
        amounts,
        userData
        );
    }
}




