// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IStargateRouter} from "./IStargateRouter.sol";
import {IStargateReceiver} from "./IStargateReceiver.sol";
import {BridgeAdapter} from "./BridgeAdapter.sol";
import {IFundsCollector} from "./IFundsCollector.sol";

struct StargatePoolInfo {
    address tokenAddress;
    uint256 poolId;
}

struct LayerZeroChainInfo {
    uint256 chainId;
    uint16 lzChainId;
}

contract StargateBridgeAdapter is BridgeAdapter, IStargateReceiver {
    using SafeERC20 for IERC20;

    IStargateRouter immutable _stargate;

    mapping(address => uint256) _pools;
    mapping(uint256 => uint16) _chains;

    constructor(
        address stargate_,
        StargatePoolInfo[] memory stargatePools,
        LayerZeroChainInfo[] memory layerZeroChains
    ) {
        _stargate = IStargateRouter(stargate_);

        for (uint256 i = 0; i < stargatePools.length; i++) {
            _pools[stargatePools[i].tokenAddress] = stargatePools[i].poolId;
        }

        for (uint256 i = 0; i < layerZeroChains.length; i++) {
            _chains[layerZeroChains[i].chainId] = layerZeroChains[i].lzChainId;
        }
    }

    function bridgeToken(
        GeneralParams calldata generalParams,
        SendTokenParams calldata sendTokenParams
    ) external payable {
        uint256 poolId = _getStargatePoolId(sendTokenParams.token);

        IStargateRouter.lzTxObj memory lzTxParams;
        bytes memory payload;
        {
            lzTxParams = _generateLzTxParams(generalParams.bridgeParams);
            payload = _generatePayload(
                _generateTraceId(),
                generalParams.fundsCollector,
                generalParams.withdrawalAddress,
                generalParams.owner
            );
        }

        IERC20(sendTokenParams.token).safeIncreaseAllowance(
            address(_stargate),
            sendTokenParams.amount
        );
        _stargate.swap{value: msg.value}(
            _getLayerZeroChainId(generalParams.chainId),
            poolId,
            poolId,
            payable(tx.origin),
            sendTokenParams.amount,
            (sendTokenParams.amount * sendTokenParams.slippage) / 1e4,
            lzTxParams,
            abi.encodePacked(address(this)),
            payload
        );
    }

    function sgReceive(
        uint16,
        bytes calldata,
        uint256,
        address _token,
        uint256 amountLD,
        bytes calldata payload
    ) external {
        (
            bytes32 traceId,
            address fundsCollector,
            address withdrawalAddress,
            address owner
        ) = _parsePayload(payload);
        _finishBridgeToken(
            traceId,
            _token,
            amountLD,
            fundsCollector,
            withdrawalAddress,
            owner
        );
    }

    function estimateBridgeFee(
        GeneralParams calldata generalParams,
        SendTokenParams calldata
    ) external view returns (uint256 bridgeFee) {
        (bridgeFee, ) = _stargate.quoteLayerZeroFee(
            _getLayerZeroChainId(generalParams.chainId),
            1, // TYPE_SWAP_REMOTE
            abi.encodePacked(generalParams.fundsCollector),
            _generatePayload(
                keccak256(abi.encodePacked(block.timestamp)), // some random bytes32
                generalParams.fundsCollector,
                generalParams.withdrawalAddress,
                generalParams.owner
            ),
            _generateLzTxParams(generalParams.bridgeParams)
        );
    }

    function generateBridgeParams(
        uint256 dstGasForCall
    ) external pure returns (bytes memory bridgeParams) {
        bridgeParams = abi.encode(dstGasForCall);
    }

    function _generatePayload(
        bytes32 traceId,
        address fundsCollector,
        address withdrawalAddress,
        address owner
    ) internal pure returns (bytes memory) {
        return abi.encode(traceId, fundsCollector, withdrawalAddress, owner);
    }

    function _parsePayload(
        bytes calldata payload
    )
        internal
        pure
        returns (
            bytes32 traceId,
            address fundsCollector,
            address withdrawalAddress,
            address owner
        )
    {
        (traceId, fundsCollector, withdrawalAddress, owner) = abi.decode(
            payload,
            (bytes32, address, address, address)
        );
    }

    function _generateLzTxParams(
        bytes calldata bridgeParams
    ) internal view returns (IStargateRouter.lzTxObj memory) {
        return
            IStargateRouter.lzTxObj({
                dstGasForCall: abi.decode(bridgeParams, (uint256)),
                dstNativeAmount: 0,
                dstNativeAddr: abi.encodePacked(tx.origin)
            });
    }

    function _getLayerZeroChainId(
        uint256 chainId
    ) internal view returns (uint16 lzChainId) {
        lzChainId = _chains[chainId];
        if (lzChainId == 0) revert UnsupportedChain(chainId);
    }

    function _getStargatePoolId(
        address token
    ) internal view returns (uint256 sgPoolId) {
        sgPoolId = _pools[token];
        if (sgPoolId == 0) revert UnsupportedToken(token);
    }
}

