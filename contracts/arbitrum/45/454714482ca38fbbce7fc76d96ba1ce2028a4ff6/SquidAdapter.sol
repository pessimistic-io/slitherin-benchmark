// SPDX-License-Identifier: GPL-3.0-or-later
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

    /// @inheritdoc ISushiXSwapV2Adapter
    function swap(
        uint256 _amountBridged,
        bytes calldata _swapData,
        address _token,
        bytes calldata _payloadData
    ) external payable override {
        revert();
    }

    /// @inheritdoc ISushiXSwapV2Adapter
    function executePayload(
        uint256 _amountBridged,
        bytes calldata _payloadData,
        address _token
    ) external payable override {
        revert();
    }

    /// @inheritdoc ISushiXSwapV2Adapter
    function adapterBridge(
        bytes calldata _adapterData,
        address,
        bytes calldata,
        bytes calldata
    ) external payable override {
        (address token, bytes memory squidRouterData) = abi.decode(
            _adapterData,
            (address, bytes)
        );

        if (token != NATIVE_ADDRESS) {
            IERC20(token).forceApprove(
                squidRouter,
                IERC20(token).balanceOf(address(this))
            );
        }

        (bool success, bytes memory returnBytes) = squidRouter.call{value: address(this).balance}(squidRouterData);
        if (!success) {
            assembly {
                revert(add(32, returnBytes), mload(returnBytes))
            }
        }
    }

    /// @inheritdoc ISushiXSwapV2Adapter
    function sendMessage(bytes calldata _adapterData) external override {
        revert();
    }
}
