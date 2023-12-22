// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AppStorage, LibMagpieAggregator, CelerBridgeSettings} from "./LibMagpieAggregator.sol";
import {LibAsset} from "./LibAsset.sol";
import {LibBytes} from "./LibBytes.sol";
import {LibTransferKey, TransferKey} from "./LibTransferKey.sol";
import {IMagpieCelerBridge} from "./IMagpieCelerBridge.sol";
import {IMessageBus} from "./IMessageBus.sol";
import {ILiquidityBridge} from "./ILiquidityBridge.sol";
import {IBridge} from "./IBridge.sol";
import {BridgeInArgs, BridgeOutArgs, RefundArgs} from "./data-transfer_LibCommon.sol";
import {Transaction, TransactionValidation} from "./LibTransaction.sol";

struct CelerBridgeInData {
    uint32 slippage;
    uint256 fee;
}

struct CelerBridgeOutData {
    uint256 amount;
    bytes32 srcTxHash;
}

library LibCeler {
    using LibAsset for address;
    using LibBytes for bytes;
    using LibTransferKey for TransferKey;

    event UpdateCelerBridgeSettings(address indexed sender, CelerBridgeSettings celerBridgeSettings);

    function updateSettings(CelerBridgeSettings memory celerBridgeSettings) internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        s.celerBridgeSettings = celerBridgeSettings;

        emit UpdateCelerBridgeSettings(msg.sender, celerBridgeSettings);
    }

    event AddCelerChainIds(address indexed sender, uint16[] networkIds, uint64[] chainIds);

    function addCelerChainIds(uint16[] memory networkIds, uint64[] memory chainIds) internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        uint256 i;
        uint256 l = networkIds.length;
        for (i = 0; i < l; ) {
            s.celerChainIds[networkIds[i]] = chainIds[i];

            unchecked {
                i++;
            }
        }

        emit AddCelerChainIds(msg.sender, networkIds, chainIds);
    }

    event AddMagpieCelerBridgeAddresses(
        address indexed sender,
        uint16[] networkIds,
        bytes32[] magpieCelerBridgeAddresses
    );

    function addMagpieCelerBridgeAddresses(
        uint16[] memory networkIds,
        bytes32[] memory magpieCelerBridgeAddresses
    ) internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        uint256 i;
        uint256 l = magpieCelerBridgeAddresses.length;
        for (i = 0; i < l; ) {
            s.magpieCelerBridgeAddresses[networkIds[i]] = magpieCelerBridgeAddresses[i];
            unchecked {
                i++;
            }
        }

        emit AddMagpieCelerBridgeAddresses(msg.sender, networkIds, magpieCelerBridgeAddresses);
    }

    function decodeBridgeInPayload(
        bytes memory bridgeInPayload
    ) internal pure returns (CelerBridgeInData memory bridgeInData) {
        assembly {
            mstore(bridgeInData, shr(224, mload(add(bridgeInPayload, 32))))
            mstore(add(bridgeInData, 32), mload(add(bridgeInPayload, 36)))
        }
    }

    function bridgeIn(BridgeInArgs memory bridgeInArgs) internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        CelerBridgeInData memory celerBridgeInData = decodeBridgeInPayload(bridgeInArgs.bridgeArgs.payload);

        address magpieCelerBridgeAddress = address(uint160(uint256(s.magpieCelerBridgeAddresses[s.networkId])));

        bridgeInArgs.toAssetAddress.transfer(magpieCelerBridgeAddress, bridgeInArgs.amount);

        IMagpieCelerBridge(magpieCelerBridgeAddress).deposit{value: celerBridgeInData.fee}(
            IMagpieCelerBridge.DepositArgs({
                slippage: celerBridgeInData.slippage,
                chainId: s.celerChainIds[bridgeInArgs.recipientNetworkId],
                amount: bridgeInArgs.amount,
                sender: msg.sender,
                receiver: address(uint160(uint256(s.magpieCelerBridgeAddresses[bridgeInArgs.recipientNetworkId]))),
                assetAddress: bridgeInArgs.toAssetAddress,
                transferKey: bridgeInArgs.transferKey
            })
        );
    }

    function bridgeOut(BridgeOutArgs memory bridgeOutArgs) internal returns (uint256 amount) {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        address fromAssetAddress = address(uint160(uint256(bridgeOutArgs.transaction.fromAssetAddress)));

        address magpieCelerBridgeAddress = address(uint160(uint256(s.magpieCelerBridgeAddresses[s.networkId])));

        amount = IMagpieCelerBridge(magpieCelerBridgeAddress).withdraw(
            IMagpieCelerBridge.WithdrawArgs({assetAddress: fromAssetAddress, transferKey: bridgeOutArgs.transferKey})
        );
    }
}

