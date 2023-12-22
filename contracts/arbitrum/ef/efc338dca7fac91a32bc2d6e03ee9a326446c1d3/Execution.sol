// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./AccessControl.sol";
import "./Core.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Main.sol";
import {ECDSA} from "./ECDSA.sol";
import "./console.sol";

/**
 * @title CoreFacet
 * @author Ofir Smolinsky @OfirYC
 * @notice The facet responsible for executing eHXRO payloads, interacting with users' funds and 3rd
 * party cross-chain providers. As well as enabling owners of the eHXRO contracts to whitelist new tokens
 * and bridges
 */

contract CoreFacet is AccessControlled {
    // ===============
    //      LIBS
    // ===============
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    // ===============
    //      CORE
    // ===============
    /**
     * Execute Hxro Payload AND transfer tokens along with it
     * @param inboundPayload - The inbound payload to execute
     * @param sig - The signature of the end user
     * @return bridgeRes - The result passed from the bridge, and the bridge identifier
     */
    function executeHxroPayloadWithTokens(
        InboundPayload calldata inboundPayload,
        bytes calldata sig
    ) external returns (BridgeResult memory bridgeRes) {
        Token memory tokenData = CoreStorageLib.retreive().tokens[
            inboundPayload.solToken
        ];

        if (tokenData.localAddress == address(0)) revert UnsupportedToken();

        bytes memory messageHash = inboundPayload.messageHash;

        if (keccak256(messageHash).recover(sig) != msg.sender)
            revert NotSigOwner();

        CoreStorage storage coreStorage = CoreStorageLib.retreive();

        uint256 nonce;
        assembly {
            let len := mload(messageHash)
            nonce := mload(add(messageHash, len))
        }

        if (nonce != coreStorage.nonces[msg.sender]) revert InvalidNonce();

        if (address(tokenData.bridgeProvider) == address(0))
            revert UnsupportedToken();

        IERC20(tokenData.localAddress).safeTransferFrom(
            msg.sender,
            address(this),
            inboundPayload.amount
        );

        // Token bridge adapters are always delegatecalled to
        (bool success, bytes memory res) = address(tokenData.bridgeProvider)
            .delegatecall(
                abi.encodeCall(
                    ITokenBridge.bridgeHxroPayloadWithTokens,
                    (
                        inboundPayload.solToken,
                        inboundPayload.amount,
                        msg.sender,
                        bytes.concat(inboundPayload.messageHash, sig)
                    )
                )
            );

        if (!success) revert BridgeFailed(res);

        bridgeRes = abi.decode(res, (BridgeResult));

        coreStorage.nonces[msg.sender]++;
    }

    /**
     * @notice
     * Execute Hxro Payload
     * @param payload - The payload to pass on
     * @param sig - The signature of the end user
     * @return bridgeRes - The result passed from the bridge, and the bridge identifier
     */
    function executeHxroPayload(
        bytes calldata payload,
        bytes calldata sig
    ) external returns (BridgeResult memory bridgeRes) {
        bytes memory messageHash = payload;

        if (keccak256(messageHash).recover(sig) != msg.sender)
            revert NotSigOwner();

        CoreStorage storage coreStorage = CoreStorageLib.retreive();

        uint256 nonce;
        assembly {
            let len := mload(messageHash)
            nonce := mload(add(mload(messageHash), len))
        }

        if (nonce != coreStorage.nonces[msg.sender]) revert InvalidNonce();

        IPayloadBridge bridgeProvider = coreStorage.plainBridgeProvider;
        if (address(bridgeProvider) == address(0)) revert UnsupportedToken();

        IPayloadBridge plainBridge = coreStorage.plainBridgeProvider;

        bridgeRes = plainBridge.bridgeHXROPayload(
            bytes.concat(payload, sig), // HXRO payload convention always includes the sig
            msg.sender
        );

        coreStorage.nonces[msg.sender]++;
    }
}

