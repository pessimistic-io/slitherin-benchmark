// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

/**
 * @title ISocket
 * @notice An interface for a cross-chain communication contract
 * @dev This interface provides methods for transmitting and executing messages between chains,
 * connecting a plug to a remote chain and setting up switchboards for the message transmission
 * This interface also emits events for important operations such as message transmission, execution status,
 * and plug connection
 */
interface ISocket {
    /**
     * @notice registers a message
     * @dev Packs the message and includes it in a packet with capacitor
     * @param remoteChainSlug_ the remote chain slug
     * @param minMsgGasLimit_ the gas limit needed to execute the payload on remote
     * @param payload_ the data which is needed by plug at inbound call on remote
     */
    function outbound(
        uint32 remoteChainSlug_,
        uint256 minMsgGasLimit_,
        bytes32 executionParams_,
        bytes32 transmissionParams_,
        bytes calldata payload_
    ) external payable returns (bytes32 msgId);

    /**
     * @notice sets the config specific to the plug
     * @param siblingChainSlug_ the sibling chain slug
     * @param siblingPlug_ address of plug present at sibling chain to call inbound
     * @param inboundSwitchboard_ the address of switchboard to use for receiving messages
     * @param outboundSwitchboard_ the address of switchboard to use for sending messages
     */
    function connect(
        uint32 siblingChainSlug_,
        address siblingPlug_,
        address inboundSwitchboard_,
        address outboundSwitchboard_
    ) external;

    event PlugConnected(
        address plug,
        uint32 siblingChainSlug,
        address siblingPlug,
        address inboundSwitchboard,
        address outboundSwitchboard,
        address capacitor,
        address decapacitor
    );
}

