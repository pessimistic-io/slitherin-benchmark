// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AppStorage, LibMagpieAggregator, WormholeBridgeSettings} from "./LibMagpieAggregator.sol";
import {LibAsset} from "./LibAsset.sol";
import {LibBytes} from "./LibBytes.sol";
import {LibTransferKey} from "./LibTransferKey.sol";
import {IWormhole} from "./IWormhole.sol";
import {IWormholeCore} from "./IWormholeCore.sol";
import {BridgeInArgs, BridgeOutArgs} from "./data-transfer_LibCommon.sol";
import {Transaction, TransactionValidation} from "./LibTransaction.sol";

struct WormholeBridgeInData {
    uint16 recipientBridgeChainId;
}

error WormholeInvalidAssetAddress();

library LibWormhole {
    using LibAsset for address;
    using LibBytes for bytes;

    event UpdateWormholeBridgeSettings(address indexed sender, WormholeBridgeSettings wormholeBridgeSettings);

    function updateSettings(WormholeBridgeSettings memory wormholeBridgeSettings) internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        s.wormholeBridgeSettings = wormholeBridgeSettings;

        emit UpdateWormholeBridgeSettings(msg.sender, wormholeBridgeSettings);
    }

    function normalize(uint8 fromDecimals, uint8 toDecimals, uint256 amount) private pure returns (uint256) {
        amount /= 10 ** (fromDecimals - toDecimals);
        return amount;
    }

    function denormalize(uint8 fromDecimals, uint8 toDecimals, uint256 amount) private pure returns (uint256) {
        amount *= 10 ** (toDecimals - fromDecimals);
        return amount;
    }

    function getRecipientBridgeChainId(
        bytes memory bridgeInPayload
    ) private pure returns (uint16 recipientBridgeChainId) {
        assembly {
            recipientBridgeChainId := shr(240, mload(add(bridgeInPayload, 32)))
        }
    }

    function bridgeIn(BridgeInArgs memory bridgeInArgs) internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        uint256 amount = bridgeInArgs.amount;

        // Dust management
        uint8 toAssetDecimals = bridgeInArgs.toAssetAddress.getDecimals();
        if (toAssetDecimals > 8) {
            amount = normalize(toAssetDecimals, 8, amount);
            amount = denormalize(8, toAssetDecimals, amount);
        }

        bridgeInArgs.toAssetAddress.approve(s.wormholeBridgeSettings.bridgeAddress, amount);
        uint64 tokenSequence = IWormhole(s.wormholeBridgeSettings.bridgeAddress).transferTokensWithPayload(
            bridgeInArgs.toAssetAddress,
            amount,
            getRecipientBridgeChainId(bridgeInArgs.bridgeArgs.payload),
            s.magpieAggregatorAddresses[bridgeInArgs.recipientNetworkId],
            uint32(block.timestamp % 2 ** 32),
            LibTransferKey.encode(bridgeInArgs.transferKey)
        );

        s.wormholeTokenSequences[bridgeInArgs.transferKey.swapSequence] = tokenSequence;
    }

    function bridgeOut(BridgeOutArgs memory bridgeOutArgs) internal returns (uint256 amount) {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        // We dont have to verify because completeTransfer will do it
        IWormholeCore.VM memory vm = IWormholeCore(s.wormholeSettings.bridgeAddress).parseVM(
            bridgeOutArgs.bridgeArgs.payload
        );

        bytes32 bridgeAssetAddress;
        bytes memory vmPayload = vm.payload;
        assembly {
            amount := mload(add(vmPayload, 33))
            bridgeAssetAddress := mload(add(vmPayload, 65))
        }

        address assetAddress = address(uint160(uint256(bridgeOutArgs.transaction.fromAssetAddress)));

        if (
            IWormhole(s.wormholeBridgeSettings.bridgeAddress).wrappedAsset(vm.emitterChainId, bridgeAssetAddress) !=
            assetAddress
        ) {
            revert WormholeInvalidAssetAddress();
        }

        LibTransferKey.validate(bridgeOutArgs.transferKey, LibTransferKey.decode(vm.payload.slice(133, 42)));

        uint8 fromAssetDecimals = assetAddress.getDecimals();
        if (fromAssetDecimals > 8) {
            amount = denormalize(8, fromAssetDecimals, amount);
        }

        IWormhole(s.wormholeBridgeSettings.bridgeAddress).completeTransfer(bridgeOutArgs.bridgeArgs.payload);
    }

    function getTokenSequence(uint64 swapSequence) internal view returns (uint64) {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        return s.wormholeTokenSequences[swapSequence];
    }
}

