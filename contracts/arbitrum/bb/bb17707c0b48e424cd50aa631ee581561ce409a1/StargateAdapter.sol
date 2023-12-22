// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./IRouteProcessor.sol";
import "./IWETH.sol";
import "./SafeERC20.sol";

import "./ISushiXSwapV2Adapter.sol";
import "./IStargateRouter.sol";
import "./IStargateReceiver.sol";
import "./IStargateWidget.sol";
import "./IStargateEthVault.sol";

contract StargateAdapter is ISushiXSwapV2Adapter, IStargateReceiver {
    using SafeERC20 for IERC20;

    IStargateRouter public immutable stargateRouter;
    IStargateWidget public immutable stargateWidget;
    address public immutable sgeth;
    IRouteProcessor public immutable rp;
    IWETH public immutable weth;

    address constant NATIVE_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct StargateTeleportParams {
        uint16 dstChainId; // stargate dst chain id
        address token; // token getting bridged
        uint256 srcPoolId; // stargate src pool id
        uint256 dstPoolId; // stargate dst pool id
        uint256 amount; // amount to bridge
        uint256 amountMin; // amount to bridge minimum
        uint256 dustAmount; // native token to be received on dst chain
        address receiver;
        address to;
        uint256 gas; // extra gas to be sent for dst chain operations
    }

    error InsufficientGas();
    error NotStargateRouter();
    error RpSentNativeIn();

    constructor(
        address _stargateRouter,
        address _stargateWidget,
        address _sgeth,
        address _rp,
        address _weth
    ) {
        stargateRouter = IStargateRouter(_stargateRouter);
        stargateWidget = IStargateWidget(_stargateWidget);
        sgeth = _sgeth;
        rp = IRouteProcessor(_rp);
        weth = IWETH(_weth);
    }

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
        if (_token == sgeth) {
            weth.deposit{value: _amountBridged}();
        }
        // increase token approval to RP
        IERC20(rpd.tokenIn).safeIncreaseAllowance(address(rp), _amountBridged);

        rp.processRoute(
            rpd.tokenIn,
            _amountBridged != 0 ? _amountBridged: rpd.amountIn,
            rpd.tokenOut,
            rpd.amountOutMin,
            rpd.to,
            rpd.route
        );

        // tokens should be sent via rp
        if (_payloadData.length > 0) {
            PayloadData memory pd = abi.decode(_payloadData, (PayloadData));
            try
                IPayloadExecutor(pd.target).onPayloadReceive(pd.targetData)
            {} catch (bytes memory) {
                revert();
            }
        }
    }

    /// @notice Get the fees to be paid in native token for the swap
    /// @param _dstChainId stargate dst chainId
    /// @param _functionType stargate Function type 1 for swap.
    /// See more at https://stargateprotocol.gitbook.io/stargate/developers/function-types
    /// @param _receiver receiver on the dst chain
    /// @param _gas extra gas being sent
    /// @param _dustAmount dust amount to be received at the dst chain
    /// @param _payload payload being sent at the dst chain
    function getFee(
        uint16 _dstChainId,
        uint8 _functionType,
        address _receiver,
        uint256 _gas,
        uint256 _dustAmount,
        bytes memory _payload
    ) external view returns (uint256 a, uint256 b) {
        (a, b) = stargateRouter.quoteLayerZeroFee(
            _dstChainId,
            _functionType,
            abi.encodePacked(_receiver),
            abi.encode(_payload),
            IStargateRouter.lzTxObj(
                _gas,
                _dustAmount,
                abi.encodePacked(_receiver)
            )
        );
    }

    function adapterBridge(
        bytes calldata _adapterData,
        bytes calldata _swapData,
        bytes calldata _payloadData
    ) external payable override {
        StargateTeleportParams memory params = abi.decode(
            _adapterData,
            (StargateTeleportParams)
        );

        if (params.token == NATIVE_ADDRESS) {
            // RP should not send native in, since we won't know the amount from dust
            if (params.amount == 0) revert RpSentNativeIn();
            IStargateEthVault(sgeth).deposit{value: params.amount}();
            params.token = sgeth;
        } else if (params.token == address(weth)) {
            // this case is for when rp sends weth in
            if (params.amount == 0) params.amount = weth.balanceOf(address(this));
            weth.withdraw(params.amount);
            IStargateEthVault(sgeth).deposit{value: params.amount}();
            params.token = sgeth;    
        }

        IERC20(params.token).safeApprove(
            address(stargateRouter),
            params.amount != 0
                ? params.amount
                : IERC20(params.token).balanceOf(address(this))
        );

        bytes memory payload = bytes("");
        if (_swapData.length > 0 || _payloadData.length > 0) {
            /// @dev dst gas should be more than 100k
            if (params.gas < 100000) revert InsufficientGas();
            payload = abi.encode(params.to, _swapData, _payloadData);
        }

        stargateRouter.swap{value: address(this).balance}(
            params.dstChainId,
            params.srcPoolId,
            params.dstPoolId,
            payable(tx.origin), // refund address
            params.amount != 0
                ? params.amount
                : IERC20(params.token).balanceOf(address(this)),
            params.amountMin,
            IStargateRouter.lzTxObj(
                params.gas,
                params.dustAmount,
                abi.encodePacked(params.receiver)
            ),
            abi.encodePacked(params.receiver),
            payload
        );

        stargateWidget.partnerSwap(0x0001);
    }

    /// @notice Receiver function on dst chain
    /// @param _token bridge token received
    /// @param amountLD amount received
    /// @param payload ABI-Encoded data received from src chain
    function sgReceive(
        uint16,
        bytes memory,
        uint256,
        address _token,
        uint256 amountLD,
        bytes memory payload
    ) external {
        if (msg.sender != address(stargateRouter)) revert NotStargateRouter();

        (address to, bytes memory _swapData, bytes memory _payloadData) = abi
            .decode(payload, (address, bytes, bytes));

        uint256 reserveGas = 100000;
        bool failed;

        if (gasleft() < reserveGas || _swapData.length == 0) {
            if (_token != sgeth) {
                IERC20(_token).safeTransfer(to, amountLD);
            }

            /// @dev transfer any native token received as dust to the to address
            if (address(this).balance > 0)
                to.call{value: (address(this).balance)}("");

            failed = true;
            return;
        }

        // 100000 -> exit gas
        uint256 limit = gasleft() - reserveGas;
        
        //todo: what if you had payload data for another adapter, but no swapData?
        if (_swapData.length > 0) {
            try
                ISushiXSwapV2Adapter(address(this)).swap{gas: limit}(
                    amountLD,
                    _swapData,
                    _token,
                    _payloadData
                )
            {} catch (bytes memory) {
                if (_token != sgeth) {
                    IERC20(_token).safeTransfer(to, amountLD);
                }
                failed = true;
            }
        }

        /// @dev transfer any native token received as dust to the to address
        if (address(this).balance > 0)
            to.call{value: (address(this).balance)}("");
    }

    function sendMessage(bytes calldata _adapterData) external {
        (_adapterData);
        revert();
    }

    receive() external payable {}
}

