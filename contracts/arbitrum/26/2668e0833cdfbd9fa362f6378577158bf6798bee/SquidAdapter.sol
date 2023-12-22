// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./ISushiXSwapV2Adapter.sol";
import "./SafeERC20.sol";

contract SquidAdapter is ISushiXSwapV2Adapter {
    using SafeERC20 for IERC20;

    address public immutable squidRouter;

    address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor(address _squidRouter) {
        squidRouter = _squidRouter;
    }

    function swap(
        bytes calldata _swapData,
        address _token,
        bytes calldata _payloadData
    ) external override {
        revert();
    }

    function adapterBridge(
        bytes calldata _adapterData,
        bytes calldata,
        bytes calldata
    ) external payable override {
        (address token, bytes memory squidRouterData) = abi.decode(
            _adapterData,
            (address, bytes)
        );

        if (token != NATIVE_ADDRESS) {
            IERC20(token).safeApprove(
                squidRouter,
                IERC20(token).balanceOf(address(this))
            );
        }

        squidRouter.call{value: address(this).balance}(squidRouterData);
    }

    function sendMessage(bytes calldata _adapterData) external override {
        revert();
    }
}

