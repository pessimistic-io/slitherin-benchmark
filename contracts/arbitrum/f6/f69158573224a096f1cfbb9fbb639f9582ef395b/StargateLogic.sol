// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IStargateComposer} from "./IStargateComposer.sol";
import {IStargateFactory} from "./IStargateFactory.sol";
import {IStargatePool} from "./IStargatePool.sol";

import {IStargateLogic} from "./IStargateLogic.sol";

import {BridgeLogicBase} from "./BridgeLogicBase.sol";
import {TransferHelper} from "./TransferHelper.sol";

/// @title StargateLogic
contract StargateLogic is IStargateLogic, BridgeLogicBase {
    // =========================
    // Storage
    // =========================

    /// @dev Storage position for the stargate logic, to avoid collisions in storage.
    /// @dev Uses the "magic" constant to find a unique storage slot.
    bytes32 private immutable STARGATE_LOGIC_STORAGE_POSITION =
        keccak256("vault.stargatelogic.storage");

    /// @dev Fetches the common storage for the StargateLogic.
    /// @dev Uses inline assembly to point to the specific storage slot.
    /// @return s The storage slot for StargateLogicStorage structure.
    function _getStargateStorage()
        private
        view
        returns (StargateLogicStorage storage s)
    {
        bytes32 position = STARGATE_LOGIC_STORAGE_POSITION;
        assembly ("memory-safe") {
            s.slot := position
        }
    }

    // =========================
    // Constructor
    // =========================

    /// @dev Address of the stargate composer for cross-chain messaging
    IStargateComposer private immutable stargateComposer;

    /// @notice Initializes the contract with the stargate composer and ditto stargate receiver addresses.
    /// @param _stargateComposer: Address of the stargate composer.
    /// @param _dittoStargateReceiver: Address of the ditto stargate receiver.
    constructor(
        address _stargateComposer,
        address _dittoStargateReceiver
    ) BridgeLogicBase(_dittoStargateReceiver) {
        stargateComposer = IStargateComposer(_stargateComposer);
    }

    // =========================
    // Main functions
    // =========================

    /// @inheritdoc IStargateLogic
    function sendStargateMessage(
        uint256 vaultVersion,
        uint16 dstChainId,
        uint256 srcPoolId,
        uint256 dstPoolId,
        uint256 bridgeAmount,
        uint256 amountOutMinSg,
        IStargateComposer.lzTxObj calldata lzTxParams,
        bytes calldata payload
    ) external payable onlyVaultItself {
        (address owner, uint16 vaultId) = _validateBridgeCall(
            StargateLogic_VaultCannotUseCrossChainLogic.selector
        );

        bytes memory newPayload = abi.encode(
            owner,
            vaultVersion,
            vaultId,
            payload
        );

        (uint256 fee, ) = stargateComposer.quoteLayerZeroFee(
            dstChainId,
            1,
            abi.encodePacked(dittoReceiver),
            newPayload,
            lzTxParams
        );

        TransferHelper.safeApprove(
            IStargatePool(
                IStargateFactory(stargateComposer.factory()).getPool(srcPoolId)
            ).token(),
            address(stargateComposer),
            bridgeAmount
        );

        stargateComposer.swap{value: fee}(
            dstChainId,
            srcPoolId,
            dstPoolId,
            payable(address(this)),
            bridgeAmount,
            amountOutMinSg,
            lzTxParams,
            abi.encodePacked(dittoReceiver),
            newPayload
        );
    }

    /// @inheritdoc IStargateLogic
    function stargateMultisender(
        uint256 bridgeAmount,
        MultisenderParams calldata mParams
    ) external payable onlyVaultItself {
        if (mParams.recipients.length != mParams.tokenShares.length) {
            revert StargateLogic_MultisenderParamsDoNotMatchInLength();
        }

        StargateLogicStorage storage s = _getStargateStorage();

        if (s.bridgedAmount > 0) {
            bridgeAmount = s.bridgedAmount;
        }

        // empty lzTxParams
        IStargateComposer.lzTxObj memory lzTxParams;

        // gets a quote for just transferring tokens to recipient for one stargate swap
        (uint256 fee, ) = stargateComposer.quoteLayerZeroFee(
            mParams.dstChainId,
            1,
            abi.encodePacked(address(0)),
            bytes(""),
            lzTxParams
        );

        // check if the fee is enough to cover all recipients
        if (fee * mParams.recipients.length > address(this).balance) {
            revert StargateLogic_NotEnoughBalanceForFee();
        }

        TransferHelper.safeApprove(
            IStargatePool(
                IStargateFactory(stargateComposer.factory()).getPool(
                    mParams.srcPoolId
                )
            ).token(),
            address(stargateComposer),
            bridgeAmount
        );

        uint256 amount;

        // send tokens to stargate for each recipient
        for (uint256 i; i < mParams.recipients.length; ) {
            unchecked {
                amount = (bridgeAmount * mParams.tokenShares[i]) / 1e18;

                stargateComposer.swap{value: fee}(
                    mParams.dstChainId,
                    mParams.srcPoolId,
                    mParams.dstPoolId,
                    payable(address(this)),
                    amount,
                    (amount * mParams.slippageE18) / 1e18,
                    lzTxParams,
                    abi.encodePacked(mParams.recipients[i]),
                    bytes("")
                );

                ++i;
            }
        }
    }

    /// @inheritdoc IStargateLogic
    function stargateMulticall(
        uint256 bridgedAmount,
        bytes[] calldata data
    ) external {
        if (msg.sender != dittoReceiver) {
            revert StargateLogic_OnlyDittoBridgeReceiverCanCallThisMethod();
        }

        _validateBridgeCall(
            StargateLogic_VaultCannotUseCrossChainLogic.selector
        );

        StargateLogicStorage storage s = _getStargateStorage();

        // cache bridged amount value to storage for specified stargate methods
        s.bridgedAmount = bridgedAmount;

        _multicall(data);

        // clear cached bridged amount value from storage
        s.bridgedAmount = 0;
    }
}

