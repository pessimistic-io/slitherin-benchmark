// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "./CrossLedgerVault.sol";
import "./LzMessages.sol";

/// @author YLDR <admin@apyflow.com>
contract SlaveCrossLedgerVault is CrossLedgerVault {
    using LzMessages for bytes;
    using LzMessages for UpdateMessage;
    using LzMessages for DepositedFromBridgeMessage;

    uint256 public immutable masterChainId;

    constructor(IRootVault _rootVault, uint256 _masterChainId, address _lzEndpoint)
        CrossLedgerVault(_rootVault, _lzEndpoint)
    {
        masterChainId = _masterChainId;
    }

    // slave vault only receives funds which need to be deposited
    function _transferCompleted(bytes32, uint256 value, uint8 slippage) internal virtual override {
        _depositLocal(value, slippage);
    }

    function _depositCompleted(uint256 totalAssetsBefore, uint256 totalAssetsAfter) internal override {
        bytes memory payload = DepositedFromBridgeMessage({
            totalAssetsBefore: totalAssetsBefore,
            totalAssetsAfter: totalAssetsAfter
        }).encodeMessage();
        _lzSend(chainIdToLzChainId[masterChainId], payload, "");
    }

    function _processLzMessage(LzMessageType messageType, bytes memory data) internal virtual override {
        if (messageType == LzMessageType.REDEEM) {
            RedeemMessage memory params = abi.decode(data, (RedeemMessage));
            _redeemLocal(params.shares, params.totalSupply, params.slippage);
        } else if (messageType == LzMessageType.ZERO_DEPOSIT) {
            _depositLocal(0, 0);
        }
    }

    function _redeemCompleted(uint256 received) internal override {
        IBridgeAdapter adapter = bridgeAdapters[masterChainId];

        bytes32 transferId = adapter.sendAssets(
            received,
            address(0),
            0 // won't be used
        );

        _sendUpdateMessage(masterChainId, transferId);
    }
}

