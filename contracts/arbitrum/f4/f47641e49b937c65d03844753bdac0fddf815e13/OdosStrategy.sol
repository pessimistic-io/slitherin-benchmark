// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

import "./IOdosStrategy.sol";
import "./IOdosRouter.sol";
import "./Withdrawable.sol";

contract OdosStrategy is IOdosStrategy, Withdrawable {
    address private constant ETH_ADDR = address(0);

    //solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    function swapCompact(
        address router,
        IOdosRouter.swapTokenInfo memory tokenInfo,
        bytes calldata data
    ) external payable override returns (uint256 amountOut) {
        if (tokenInfo.inputToken != ETH_ADDR) IERC20(tokenInfo.inputToken).approve(router, tokenInfo.inputAmount);
        (bool success, bytes memory returnData) = router.call{ value: msg.value }(data);
        require(success, 'OdosStrategy: swapCompact failed');
        amountOut = abi.decode(returnData, (uint256));
        IERC20(tokenInfo.outputToken).transfer(tokenInfo.outputReceiver, amountOut);
    }

    function swap(
        address router,
        IOdosRouter.swapTokenInfo memory tokenInfo,
        bytes calldata pathDefinition,
        address executor,
        uint32 referralCode
    ) external payable override returns (uint256 amountOut) {
        if (tokenInfo.inputToken != ETH_ADDR) IERC20(tokenInfo.inputToken).approve(router, tokenInfo.inputAmount);
        return IOdosRouter(router).swap{ value: msg.value }(tokenInfo, pathDefinition, executor, referralCode);
    }

    function swapMulti(
        address router,
        IOdosRouter.inputTokenInfo[] memory inputs,
        IOdosRouter.outputTokenInfo[] memory outputs,
        uint256 valueOutMin,
        bytes calldata pathDefinition,
        address executor,
        uint32 referralCode
    ) external payable override returns (uint256[] memory amountsOut) {
        return IOdosRouter(router).swapMulti(inputs, outputs, valueOutMin, pathDefinition, executor, referralCode);
    }
}

