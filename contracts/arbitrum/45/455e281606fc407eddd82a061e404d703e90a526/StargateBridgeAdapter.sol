// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IStargateRouter} from "./IStargateRouter.sol";
import {IStargateReceiver} from "./IStargateReceiver.sol";
import {BridgeAdapter} from "./BridgeAdapter.sol";

struct LayerZeroChainInfo {
    uint256 chainId;
    uint16 lzChainId;
}

contract StargateBridgeAdapter is BridgeAdapter, IStargateReceiver {
    using SafeERC20 for IERC20;

    IStargateRouter immutable _stargate;

    mapping(uint256 => uint16) _chains;

    constructor(
        address stargate_,
        LayerZeroChainInfo[] memory layerZeroChains
    ) {
        _stargate = IStargateRouter(stargate_);

        for (uint256 i = 0; i < layerZeroChains.length; i++) {
            _chains[layerZeroChains[i].chainId] = layerZeroChains[i].lzChainId;
        }
    }

    function sendTokenWithMessage(
        Token calldata token,
        Message calldata message
    ) external payable {
        uint256 poolId;
        bytes memory payload;
        IStargateRouter.lzTxObj memory lzTxParams;
        {
            (poolId, lzTxParams) = _parseBridgeParams(message.bridgeParams);
            payload = _generatePayload(
                _generateTraceId(),
                msg.sender,
                message.content
            );
        }

        IERC20(token.address_).safeIncreaseAllowance(
            address(_stargate),
            token.amount
        );
        _stargate.swap{value: msg.value}(
            _getLayerZeroChainId(message.dstChainId),
            poolId,
            poolId,
            payable(tx.origin), // solhint-disable-line avoid-tx-origin
            token.amount,
            (token.amount * token.slippage) / 1e4,
            lzTxParams,
            abi.encodePacked(address(this)),
            payload
        );
    }

    function sgReceive(
        uint16,
        bytes calldata,
        uint256,
        address token,
        uint256 amount,
        bytes calldata payload
    ) external {
        require(msg.sender == address(_stargate));
        _finishBridgeToken(token, amount, payload);
    }

    function estimateFee(
        Token calldata,
        Message calldata message
    ) external view returns (uint256 bridgeFee) {
        (, IStargateRouter.lzTxObj memory lzTxParams) = _parseBridgeParams(
            message.bridgeParams
        );

        (bridgeFee, ) = _stargate.quoteLayerZeroFee(
            _getLayerZeroChainId(message.dstChainId),
            1, // TYPE_SWAP_REMOTE
            abi.encodePacked(address(this)),
            _generatePayload(
                keccak256(abi.encodePacked("some seed")),
                msg.sender,
                message.content
            ),
            lzTxParams
        );
    }

    function generateBridgeParams(
        uint256 poolId,
        uint256 dstGasForCall
    ) external pure returns (bytes memory bridgeParams) {
        bridgeParams = abi.encode(poolId, dstGasForCall);
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

