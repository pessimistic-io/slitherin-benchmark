// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./ISwapRouter.sol";
import "./IUniswapV3Factory.sol";
import "./IHinkal.sol";
import "./Transferer.sol";
import "./console.sol";
import "./CircomData.sol";
import "./IExternalAction.sol";
import "./IWrapper.sol";

contract UniswapExternalAction is Transferer, IExternalAction {
    ISwapRouter public immutable swapRouter;
    address hinkalAddress;
    IWrapper public immutable wrapper;

    constructor(address _hinkalAddress, address swapRouterInstance, address wrapperAddress) {
        hinkalAddress = _hinkalAddress;
        swapRouter = ISwapRouter(swapRouterInstance);
        wrapper = IWrapper(wrapperAddress);
    }

    function runAction(
        CircomData memory circomData,
        bytes memory metadata
    ) external {
        uint24 fee = abi.decode(metadata, (uint24));
        swapUniswap(fee, circomData);
    }


    function swapUniswap(
        uint24 fee,
        CircomData memory circomData
    ) public returns (uint256 swapOutput) {
        console.log(circomData.inAmount);
        console.log("swapRouter", address(swapRouter));
        console.log(circomData.inErc20TokenAddress);

        wrapCoin(circomData);

        approveERC20Token(
            circomData.inErc20TokenAddress,
            address(swapRouter),
            circomData.inAmount
        );

        console.log("before swap", circomData.outErc20TokenAddress);
        console.log(circomData.outAmount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: circomData.inErc20TokenAddress,
                tokenOut: circomData.outErc20TokenAddress,
                fee: fee,
                recipient: circomData.outErc20TokenAddress != address(wrapper) ? hinkalAddress : address(this),
                deadline: block.timestamp,
                amountIn: circomData.inAmount,
                amountOutMinimum: circomData.outAmount,
                sqrtPriceLimitX96: 0
            });

        swapOutput = swapRouter.exactInputSingle(params);

        unwrapCoinAndSend(circomData);
    }

    function wrapCoin(CircomData memory circomData) internal {
        require(
            circomData.inErc20TokenAddress != address(wrapper) &&
            circomData.outErc20TokenAddress != address(wrapper),
            "native token wrapper forbidden"
        );
        if (circomData.inErc20TokenAddress == address(0)) {
            circomData.inErc20TokenAddress = address(wrapper);
            wrapper.deposit{value: circomData.inAmount}();
        }
        if (circomData.outErc20TokenAddress == address(0)) {
            circomData.outErc20TokenAddress = address(wrapper);
        }
    }

    function unwrapCoinAndSend(CircomData memory circomData) internal {
        if (circomData.outErc20TokenAddress == address(wrapper)) {
            wrapper.withdraw(circomData.outAmount);
            transferETH(hinkalAddress, circomData.outAmount);
        }
    }

    receive() external payable {}
}

