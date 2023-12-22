// SPDX-License-Identifier: SHIFT-1.0
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IStargateReceiver} from "./IStargateReceiver.sol";
import {IStargateRouter} from "./IStargateRouter.sol";
import {BridgeAdapter} from "./BridgeAdapter.sol";
import {IBridgeAdapter} from "./IBridgeAdapter.sol";

struct LayerZeroChainInfo {
    uint256 chainId;
    uint16 lzChainId;
}

contract StargateBridgeAdapter is
    IBridgeAdapter,
    BridgeAdapter,
    IStargateReceiver
{
    using SafeERC20 for IERC20;

    IStargateRouter immutable _STARGATE;

    mapping(uint256 => uint16) _chains;

    constructor(
        address stargate_,
        LayerZeroChainInfo[] memory layerZeroChains
    ) {
        _STARGATE = IStargateRouter(stargate_);

        for (uint256 i = 0; i < layerZeroChains.length; i++) {
            _chains[layerZeroChains[i].chainId] = layerZeroChains[i].lzChainId;
        }
    }

    function sgReceive(
        uint16,
        bytes calldata,
        uint256,
        address token,
        uint256 amount,
        bytes calldata payload
    ) external {
        if (msg.sender != address(_STARGATE)) revert Unauthorized();
        _finishBridge(token, amount, payload);
    }

    /// @inheritdoc IBridgeAdapter
    function estimateFee(
        Token calldata,
        Message calldata message
    ) external view returns (uint256 bridgeFee) {
        (, IStargateRouter.lzTxObj memory lzTxParams) = _parseBridgeParams(
            message.bridgeParams
        );

        (bridgeFee, ) = _STARGATE.quoteLayerZeroFee({
            _dstChainId: _getLayerZeroChainId(message.dstChainId),
            _functionType: 1,
            _toAddress: abi.encodePacked(address(this)),
            _transferAndCallPayload: _generatePayload(
                keccak256(abi.encodePacked("some seed")),
                msg.sender,
                message.content
            ),
            _lzTxParams: lzTxParams
        });
    }

    function generateBridgeParams(
        uint256 poolId,
        uint256 dstGasForCall
    ) external pure returns (bytes memory bridgeParams) {
        bridgeParams = abi.encode(poolId, dstGasForCall);
    }

    function _startBridge(
        Token calldata token,
        Message calldata message,
        bytes32 traceId
    ) internal override {
        uint256 poolId;
        bytes memory payload;
        IStargateRouter.lzTxObj memory lzTxParams;
        {
            (poolId, lzTxParams) = _parseBridgeParams(message.bridgeParams);
            payload = _generatePayload(traceId, msg.sender, message.content);
        }

        IERC20(token.address_).safeIncreaseAllowance(
            address(_STARGATE),
            token.amount
        );
        _STARGATE.swap{value: msg.value}({
            _dstChainId: _getLayerZeroChainId(message.dstChainId),
            _srcPoolId: poolId,
            _dstPoolId: poolId,
            _refundAddress: payable(tx.origin), // solhint-disable-line avoid-tx-origin
            _amountLD: token.amount,
            _minAmountLD: (token.amount * token.slippage) / 1e4,
            _lzTxParams: lzTxParams,
            _to: abi.encodePacked(address(this)),
            _payload: payload
        });
    }

    function _parseBridgeParams(
        bytes memory bridgeParams
    )
        internal
        view
        returns (uint256 poolId, IStargateRouter.lzTxObj memory lzTxParams)
    {
        // solhint-disable-next-line avoid-tx-origin
        lzTxParams.dstNativeAddr = abi.encodePacked(tx.origin);
        (poolId, lzTxParams.dstGasForCall) = abi.decode(
            bridgeParams,
            (uint256, uint256)
        );
    }

    function _getLayerZeroChainId(
        uint256 chainId
    ) internal view returns (uint16 lzChainId) {
        lzChainId = _chains[chainId];
        if (lzChainId == 0) revert UnsupportedChain(chainId);
    }
}

