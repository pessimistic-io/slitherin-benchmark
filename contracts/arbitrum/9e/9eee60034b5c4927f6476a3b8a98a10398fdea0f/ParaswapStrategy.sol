// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

import "./IParaswapStrategy.sol";
import "./IParaswapRouter.sol";
import "./Utils.sol";

contract ParaswapStrategy is IParaswapStrategy {
    address private constant ETH_ADDR = address(0);

    //solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function simpleSwap(
        address router,
        Utils.SimpleData calldata data
    ) external payable override returns (uint256 receivedAmount) {
        if (data.fromToken != ETH_ADDR)
            IERC20(data.fromToken).approve(IParaswapRouter(router).getTokenTransferProxy(), data.fromAmount);
        return IParaswapRouter(router).simpleSwap(data);
    }
}

