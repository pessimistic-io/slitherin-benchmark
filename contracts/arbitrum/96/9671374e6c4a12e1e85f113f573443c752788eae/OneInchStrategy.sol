// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./I1InchStrategy.sol";
import "./IAggregationExecutor.sol";
import "./I1InchRouter.sol";
import "./Withdrawable.sol";

contract OneInchStrategy is I1InchStrategy, Withdrawable {
    address private constant ETH_ADDR = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    //solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function swap(
        address router,
        IAggregationExecutor executor,
        I1InchRouter.SwapDescription calldata desc,
        bytes calldata permit,
        bytes calldata data
    ) external payable override returns (uint256 returnAmount, uint256 spentAmount) {
        if (address(desc.srcToken) != ETH_ADDR) desc.srcToken.approve(router, desc.amount);
        return I1InchRouter(router).swap{ value: msg.value }(executor, desc, permit, data);
    }

    function uniswapV3Swap(
        address router,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools
    ) external payable override returns (uint256 returnAmount) {
        return I1InchRouter(router).uniswapV3Swap{ value: msg.value }(amount, minReturn, pools);
    }

    function uniswapV3SwapTo(
        address router,
        UniV3SwapTo calldata uniV3Swap
    ) external payable override returns (uint256 returnAmount) {
        if (uniV3Swap.srcToken != ETH_ADDR) IERC20(uniV3Swap.srcToken).approve(router, uniV3Swap.amount);
        return
            I1InchRouter(router).uniswapV3SwapTo{ value: msg.value }(
                uniV3Swap.recipient,
                uniV3Swap.amount,
                uniV3Swap.minReturn,
                uniV3Swap.pools
            );
    }

    function uniswapV3SwapToWithPermit(
        address router,
        address payable recipient,
        address srcToken,
        uint256 amount,
        uint256 minReturn,
        uint256[] calldata pools,
        bytes calldata permit
    ) external override returns (uint256 returnAmount) {
        IERC20(srcToken).approve(router, amount);
        return
            I1InchRouter(router).uniswapV3SwapToWithPermit(
                recipient,
                IERC20(srcToken),
                amount,
                minReturn,
                pools,
                permit
            );
    }
}

