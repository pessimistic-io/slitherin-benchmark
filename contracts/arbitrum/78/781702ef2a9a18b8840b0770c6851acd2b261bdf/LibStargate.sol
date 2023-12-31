// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import {AppStorage, LibMagpieAggregator, StargateSettings} from "./LibMagpieAggregator.sol";
import {LibAsset} from "./LibAsset.sol";
import {LibBytes} from "./LibBytes.sol";
import {LibTransferKey, TransferKey} from "./LibTransferKey.sol";
import {IMagpieStargateBridge} from "./IMagpieStargateBridge.sol";
import {IStargateRouter} from "./IStargateRouter.sol";
import {IStargatePool} from "./IStargatePool.sol";
import {IStargateFactory} from "./IStargateFactory.sol";
import {IStargateFeeLibrary} from "./IStargateFeeLibrary.sol";
import {BridgeInArgs, BridgeOutArgs, BridgeType} from "./data-transfer_LibCommon.sol";
import {Transaction, TransactionValidation} from "./LibTransaction.sol";

struct StargateBridgeInData {
    uint16 layerZeroRecipientChainId;
    uint256 sourcePoolId;
    uint256 destPoolId;
    uint256 fee;
}

struct StargateBridgeOutData {
    bytes srcAddress;
    uint256 nonce;
    uint16 srcChainId;
}

struct ExecuteBridgeInArgs {
    address routerAddress;
    uint256 amount;
    bytes recipientAddress;
    TransferKey transferKey;
    StargateBridgeInData bridgeInData;
    IStargateRouter.lzTxObj lzTxObj;
}

error StargateBridgeIsNotReady();
error StargateInvalidSender();

library LibStargate {
    using LibAsset for address;
    using LibBytes for bytes;

    event UpdateStargateSettings(address indexed sender, StargateSettings stargateSettings);

    function updateSettings(StargateSettings memory stargateSettings) internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        s.stargateSettings = stargateSettings;

        emit UpdateStargateSettings(msg.sender, stargateSettings);
    }

    function decodeBridgeInPayload(bytes memory bridgeInPayload)
        internal
        pure
        returns (StargateBridgeInData memory bridgeInData)
    {
        assembly {
            mstore(bridgeInData, shr(240, mload(add(bridgeInPayload, 32))))
            mstore(add(bridgeInData, 32), mload(add(bridgeInPayload, 34)))
            mstore(add(bridgeInData, 64), mload(add(bridgeInPayload, 66)))
            mstore(add(bridgeInData, 96), mload(add(bridgeInPayload, 98)))
        }
    }

    function decodeBridgeOutPayload(bytes memory bridgeOutPayload)
        internal
        pure
        returns (StargateBridgeOutData memory bridgeOutData)
    {
        uint256 nonce;
        uint16 srcChainId;

        assembly {
            nonce := mload(add(bridgeOutPayload, 72))
            srcChainId := shr(240, mload(add(bridgeOutPayload, 104)))
        }

        bridgeOutData.srcAddress = bridgeOutPayload.slice(0, 40);
        bridgeOutData.nonce = nonce;
        bridgeOutData.srcChainId = srcChainId;
    }

    function getMinAmountLD(uint256 amount, StargateBridgeInData memory bridgeInData) private view returns (uint256) {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        address stargateFactoryAddress = IStargateRouter(s.stargateSettings.routerAddress).factory();
        address poolAddress = IStargateFactory(stargateFactoryAddress).getPool(bridgeInData.sourcePoolId);
        address feeLibraryAddress = IStargatePool(poolAddress).feeLibrary();
        uint256 convertRate = IStargatePool(poolAddress).convertRate();
        IStargatePool.SwapObj memory swapObj = IStargateFeeLibrary(feeLibraryAddress).getFees(
            bridgeInData.sourcePoolId,
            bridgeInData.destPoolId,
            bridgeInData.layerZeroRecipientChainId,
            address(this),
            amount / convertRate
        );
        swapObj.amount =
            (amount / convertRate - (swapObj.eqFee + swapObj.protocolFee + swapObj.lpFee) + swapObj.eqReward) *
            convertRate;
        return swapObj.amount;
    }

    function encodeRecipientAddress(bytes32 recipientAddress)
        private
        pure
        returns (bytes memory encodedRecipientAddress)
    {
        encodedRecipientAddress = new bytes(20);

        assembly {
            mstore(add(encodedRecipientAddress, 32), shl(96, recipientAddress))
        }
    }

    function getLzTxObj(address sender) private pure returns (IStargateRouter.lzTxObj memory lzTxObj) {
        bytes memory encodedSender = new bytes(20);

        assembly {
            mstore(add(encodedSender, 32), shl(96, sender))
        }

        lzTxObj = IStargateRouter.lzTxObj(0, 0, encodedSender);
    }

    function bridgeIn(BridgeInArgs memory bridgeInArgs) internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        bridgeInArgs.toAssetAddress.approve(s.stargateSettings.routerAddress, bridgeInArgs.amount);

        executeBridgeIn(
            ExecuteBridgeInArgs({
                recipientAddress: encodeRecipientAddress(
                    s.magpieStargateBridgeAddresses[bridgeInArgs.recipientNetworkId]
                ),
                bridgeInData: decodeBridgeInPayload(bridgeInArgs.bridgeArgs.payload),
                lzTxObj: getLzTxObj(msg.sender),
                amount: bridgeInArgs.amount,
                routerAddress: s.stargateSettings.routerAddress,
                transferKey: bridgeInArgs.transferKey
            })
        );
    }

    function executeBridgeIn(ExecuteBridgeInArgs memory executeBridgeInArgs) internal {
        IStargateRouter(executeBridgeInArgs.routerAddress).swap{value: executeBridgeInArgs.bridgeInData.fee}(
            executeBridgeInArgs.bridgeInData.layerZeroRecipientChainId,
            executeBridgeInArgs.bridgeInData.sourcePoolId,
            executeBridgeInArgs.bridgeInData.destPoolId,
            payable(msg.sender),
            executeBridgeInArgs.amount,
            getMinAmountLD(executeBridgeInArgs.amount, executeBridgeInArgs.bridgeInData),
            executeBridgeInArgs.lzTxObj,
            executeBridgeInArgs.recipientAddress,
            LibTransferKey.encode(executeBridgeInArgs.transferKey)
        );
    }

    function bridgeOut(BridgeOutArgs memory bridgeOutArgs) internal returns (uint256 amount) {
        AppStorage storage s = LibMagpieAggregator.getStorage();
        StargateBridgeOutData memory bridgeOutData = decodeBridgeOutPayload(bridgeOutArgs.bridgeArgs.payload);

        address fromAssetAddress = address(uint160(uint256(bridgeOutArgs.transaction.fromAssetAddress)));

        amount = IMagpieStargateBridge(address(uint160(uint256(s.magpieStargateBridgeAddresses[s.networkId]))))
            .withdraw(
                IMagpieStargateBridge.WithdrawArgs({
                    assetAddress: fromAssetAddress,
                    srcAddress: bridgeOutData.srcAddress,
                    nonce: bridgeOutData.nonce,
                    srcChainId: bridgeOutData.srcChainId,
                    transferKey: bridgeOutArgs.transferKey
                })
            );
    }

    event AddMagpieStargateBridgeAddresses(
        address indexed sender,
        uint16[] networkIds,
        bytes32[] magpieStargateBridgeAddresses
    );

    function addMagpieStargateBridgeAddresses(
        uint16[] memory networkIds,
        bytes32[] memory magpieStargateBridgeAddresses
    ) internal {
        AppStorage storage s = LibMagpieAggregator.getStorage();

        uint256 i;
        uint256 l = magpieStargateBridgeAddresses.length;
        for (i = 0; i < l; ) {
            s.magpieStargateBridgeAddresses[networkIds[i]] = magpieStargateBridgeAddresses[i];

            unchecked {
                i++;
            }
        }

        emit AddMagpieStargateBridgeAddresses(msg.sender, networkIds, magpieStargateBridgeAddresses);
    }
}

