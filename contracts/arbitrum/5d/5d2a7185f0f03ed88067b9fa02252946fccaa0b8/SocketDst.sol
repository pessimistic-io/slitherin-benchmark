// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.7;

import "./IDecapacitor.sol";
import "./IPlug.sol";

import "./SocketBase.sol";

abstract contract SocketDst is SocketBase {
    error AlreadyAttested();
    error InvalidProof();
    error InvalidRetry();
    error MessageAlreadyExecuted();
    error NotExecutor();
    error VerificationFailed();

    // msgId => message status
    mapping(bytes32 => bool) public messageExecuted;
    // capacitorAddr|chainSlug|packetId
    mapping(bytes32 => bytes32) public override packetIdRoots;
    mapping(bytes32 => uint256) public rootProposedAt;

    /**
     * @notice emits the packet details when proposed at remote
     * @param transmitter address of transmitter
     * @param packetId packet id
     * @param root packet root
     */
    event PacketProposed(
        address indexed transmitter,
        bytes32 indexed packetId,
        bytes32 root
    );

    /**
     * @notice emits the root details when root is replaced by owner
     * @param packetId packet id
     * @param oldRoot old root
     * @param newRoot old root
     */
    event PacketRootUpdated(bytes32 packetId, bytes32 oldRoot, bytes32 newRoot);

    function propose(
        bytes32 packetId_,
        bytes32 root_,
        bytes calldata signature_
    ) external {
        if (packetIdRoots[packetId_] != bytes32(0)) revert AlreadyAttested();

        (address transmitter, bool isTransmitter) = transmitManager__
            .checkTransmitter(
                uint32(_decodeSlug(packetId_)),
                keccak256(abi.encode(chainSlug, packetId_, root_)),
                signature_
            );

        if (!isTransmitter) revert InvalidAttester();

        packetIdRoots[packetId_] = root_;
        rootProposedAt[packetId_] = block.timestamp;

        emit PacketProposed(transmitter, packetId_, root_);
    }

    /**
     * @notice executes a message, fees will go to recovered executor address
     * @param packetId_ packet id
     * @param localPlug_ remote plug address
     * @param messageDetails_ the details needed for message verification
     */
    function execute(
        bytes32 packetId_,
        address localPlug_,
        ISocket.MessageDetails calldata messageDetails_,
        bytes memory signature_
    ) external override {
        if (messageExecuted[messageDetails_.msgId])
            revert MessageAlreadyExecuted();
        messageExecuted[messageDetails_.msgId] = true;

        uint256 remoteSlug = _decodeSlug(messageDetails_.msgId);

        PlugConfig storage plugConfig = _plugConfigs[localPlug_][remoteSlug];

        bytes32 packedMessage = hasher__.packMessage(
            remoteSlug,
            plugConfig.siblingPlug,
            chainSlug,
            localPlug_,
            messageDetails_.msgId,
            messageDetails_.msgGasLimit,
            messageDetails_.executionFee,
            messageDetails_.payload
        );

        (address executor, bool isValidExecutor) = executionManager__
            .isExecutor(packedMessage, signature_);
        if (!isValidExecutor) revert NotExecutor();

        _verify(
            packetId_,
            remoteSlug,
            packedMessage,
            plugConfig,
            messageDetails_.decapacitorProof
        );
        _execute(
            executor,
            messageDetails_.executionFee,
            localPlug_,
            remoteSlug,
            messageDetails_.msgGasLimit,
            messageDetails_.msgId,
            messageDetails_.payload
        );
    }

    function _verify(
        bytes32 packetId_,
        uint256 remoteChainSlug_,
        bytes32 packedMessage_,
        PlugConfig storage plugConfig_,
        bytes memory decapacitorProof_
    ) internal view {
        if (
            !ISwitchboard(plugConfig_.inboundSwitchboard__).allowPacket(
                packetIdRoots[packetId_],
                packetId_,
                uint32(remoteChainSlug_),
                rootProposedAt[packetId_]
            )
        ) revert VerificationFailed();

        if (
            !plugConfig_.decapacitor__.verifyMessageInclusion(
                packetIdRoots[packetId_],
                packedMessage_,
                decapacitorProof_
            )
        ) revert InvalidProof();
    }

    function _execute(
        address executor,
        uint256 executionFee,
        address localPlug_,
        uint256 remoteChainSlug_,
        uint256 msgGasLimit_,
        bytes32 msgId_,
        bytes calldata payload_
    ) internal {
        try
            IPlug(localPlug_).inbound{gas: msgGasLimit_}(
                remoteChainSlug_,
                payload_
            )
        {
            executionManager__.updateExecutionFees(
                executor,
                executionFee,
                msgId_
            );
            emit ExecutionSuccess(msgId_);
        } catch Error(string memory reason) {
            // catch failing revert() and require()
            messageExecuted[msgId_] = false;
            emit ExecutionFailed(msgId_, reason);
        } catch (bytes memory reason) {
            // catch failing assert()
            messageExecuted[msgId_] = false;
            emit ExecutionFailedBytes(msgId_, reason);
        }
    }

    function isPacketProposed(bytes32 packetId_) external view returns (bool) {
        return packetIdRoots[packetId_] == bytes32(0) ? false : true;
    }

    function _decodeSlug(
        bytes32 id_
    ) internal pure returns (uint256 chainSlug_) {
        chainSlug_ = uint256(id_) >> 224;
    }
}

