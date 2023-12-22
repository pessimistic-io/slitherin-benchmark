// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "./ISushiXSwapV2Adapter.sol";
import "./IRouteProcessor.sol";
import "./SafeERC20.sol";

contract SquidAdapter is ISushiXSwapV2Adapter {
    using SafeERC20 for IERC20;

    address public immutable squidRouter;
    address public immutable squidMulticall;
    IRouteProcessor public immutable rp;

    address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    error NotSquidCaller();

    constructor(address _squidRouter, address _squidMulticall, address _rp) {
        squidRouter = _squidRouter;
        squidMulticall = _squidMulticall;
        rp = IRouteProcessor(_rp);
    }

    /// @inheritdoc ISushiXSwapV2Adapter
    function swap(
        uint256 _amountBridged,
        bytes calldata _swapData,
        address _token,
        bytes calldata _payloadData
    ) external payable override {
        IRouteProcessor.RouteProcessorData memory rpd = abi.decode(
            _swapData,
            (IRouteProcessor.RouteProcessorData)
        );

        // send tokens to RP
        IERC20(rpd.tokenIn).safeTransfer(address(rp), _amountBridged);

        rp.processRoute(
            rpd.tokenIn,
            _amountBridged,
            rpd.tokenOut,
            rpd.amountOutMin,
            rpd.to,
            rpd.route
        );

        // tokens should be sent via rp
        if (_payloadData.length > 0) {
            PayloadData memory pd = abi.decode(_payloadData, (PayloadData));
            try
                IPayloadExecutor(pd.target).onPayloadReceive{gas: pd.gasLimit}(
                    pd.targetData
                )
            {} catch (bytes memory) {
                revert();
            }
        }
    }

    /// @inheritdoc ISushiXSwapV2Adapter
    function executePayload(
        uint256 _amountBridged,
        bytes calldata _payloadData,
        address _token
    ) external payable override {
        PayloadData memory pd = abi.decode(_payloadData, (PayloadData));
        IERC20(_token).safeTransfer(pd.target, _amountBridged);
        IPayloadExecutor(pd.target).onPayloadReceive{gas: pd.gasLimit}(
            pd.targetData
        );
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

        (bool success, bytes memory result) = squidRouter.call{value: address(this).balance}(squidRouterData);
        if (!success) {
            if (result.length == 0) revert();
            assembly {
                revert(add(32, result), mload(result))
            }
        }
    }

    /// @notice Receiver function on dst chain
    /// @param
    /// @param
    /// @param payload payload data
    /// @param
    /// @param amount bridged token amount
    function executeWithToken(
        string calldata,
        string calldata,
        bytes calldata payload,
        string calldata,
        uint256 amount
    ) external {
        uint256 gasLeft = gasleft();
        if (msg.sender != address(squidRouter) && msg.sender != address(squidMulticall))
            revert NotSquidCaller();

        (address to, address _token, bytes memory _swapData, bytes memory _payloadData) = abi
            .decode(payload, (address, address, bytes, bytes));

        uint256 reserveGas = 100000;

        if (gasLeft < reserveGas) {
            IERC20(_token).safeTransfer(to, amount);

            /// @dev transfer any native token
            if (address(this).balance > 0)
                to.call{value: (address(this).balance)}("");

            return;
        }

        // 100000 -> exit gas
        uint256 limit = gasLeft - reserveGas;

        if (_swapData.length > 0) {
            try
                ISushiXSwapV2Adapter(address(this)).swap{gas: limit}(
                    amount,
                    _swapData,
                    _token,
                    _payloadData
                )
            {} catch (bytes memory) {}
        } else if (_payloadData.length > 0) {
            try
                ISushiXSwapV2Adapter(address(this)).executePayload{gas: limit}(
                    amount,
                    _payloadData,
                    _token
                )
            {} catch (bytes memory) {}
        }

        if (IERC20(_token).balanceOf(address(this)) > 0)
            IERC20(_token).safeTransfer(to, IERC20(_token).balanceOf(address(this)));

        /// @dev transfer any native token received as dust to the to address
        if (address(this).balance > 0)
            to.call{value: (address(this).balance)}("");
    }

    /// @inheritdoc ISushiXSwapV2Adapter
    function sendMessage(bytes calldata _adapterData) external override {
        revert();
    }
}

