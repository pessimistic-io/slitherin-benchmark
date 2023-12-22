// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IBridge.sol";
import "./IXybridge.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./LibData.sol";
import "./LibPlexusUtil.sol";
import "./console.sol";

contract XyBridgeFacet is IBridge, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IXybridge private immutable xybridge;

    constructor(IXybridge _xybridge) {
        xybridge = _xybridge;
    }

    function bridgeToXybridge(BridgeData memory _bridgeData, XyBridgeData memory _xyDesc) external payable nonReentrant {
        LibPlexusUtil._isTokenDeposit(_bridgeData.srcToken, _bridgeData.amount);
        _xybridgeStart(_bridgeData, _xyDesc);
    }

    function swapAndBridgeToXybridge(
        SwapData calldata _swap,
        BridgeData memory _bridgeData,
        XyBridgeData memory _xyDesc
    ) external payable nonReentrant {
        _bridgeData.amount = LibPlexusUtil._tokenDepositAndSwap(_swap);
        _xybridgeStart(_bridgeData, _xyDesc);
    }

    function callSwapRequest(uint256 _swapId) external returns (SwapRequest memory) {
        SwapRequest memory swapRequest = xybridge.getSwapRequest(_swapId);
        return swapRequest;
    }

    function callFeeStruct(uint32 _chainId, address _token) external returns (FeeStructure memory) {
        FeeStructure memory feeStruct = xybridge.getFeeStructure(_chainId, _token);
        return feeStruct;
    }

    function callEverClosed(uint32 _chainId, uint256 _swapId) external returns (bool) {
        return xybridge.getEverClosed(_chainId, _swapId);
    }

    function _xybridgeStart(BridgeData memory _bridgeData, XyBridgeData memory _xyDesc) internal {
        bool isNotNative = !LibPlexusUtil._isNative(_bridgeData.srcToken);
        if (isNotNative) {
            IERC20(_bridgeData.srcToken).safeApprove(address(xybridge), _bridgeData.amount);
            SwapDescription memory swapDesc = SwapDescription({
                fromToken: IERC20(_bridgeData.srcToken),
                toToken: IERC20(_bridgeData.srcToken),
                receiver: _bridgeData.recipient,
                amount: _bridgeData.amount,
                minReturnAmount: _bridgeData.amount
            });
            ToChainDescription memory tcDesc = ToChainDescription({
                toChainId: uint32(_bridgeData.dstChainId),
                toChainToken: IERC20(_xyDesc.toChainToken),
                expectedToChainTokenAmount: _bridgeData.amount,
                slippage: 0
            });
            xybridge.swap(_xyDesc.aggregatorAdaptor, swapDesc, "0x", tcDesc);
            IERC20(_bridgeData.srcToken).safeApprove(address(xybridge), 0);
        } else {
            SwapDescription memory swapDesc = SwapDescription({
                fromToken: IERC20(_bridgeData.srcToken),
                toToken: IERC20(_bridgeData.srcToken),
                receiver: _bridgeData.recipient,
                amount: _bridgeData.amount,
                minReturnAmount: _bridgeData.amount
            });
            ToChainDescription memory tcDesc = ToChainDescription({
                toChainId: uint32(_bridgeData.dstChainId),
                toChainToken: IERC20(_xyDesc.toChainToken),
                expectedToChainTokenAmount: _bridgeData.amount,
                slippage: 0
            });
            xybridge.swap{value: msg.value}(_xyDesc.aggregatorAdaptor, swapDesc, "0x", tcDesc);
        }
        emit LibData.Bridge(msg.sender, _bridgeData.dstChainId, _bridgeData.srcToken, _bridgeData.amount, _bridgeData.plexusData);
    }
}

