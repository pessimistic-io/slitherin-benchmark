// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ILayerZeroReceiver.sol";
import "./ILayerZeroEndpoint.sol";
import "./Ownable.sol";

/// @title LayerZero Mailbox
/// @notice An example contract for receiving messages from other chains
contract LzMailbox is ILayerZeroReceiver, Ownable {
    event LzMessageReceived(
        uint64 indexed sequence,
        uint32 indexed sourceChainId,
        address indexed sourceAddress,
        address sender,
        address recipient,
        string message
    );

    struct Msg {
        address sender;
        string message;
    }

    ILayerZeroEndpoint public immutable lzEndpoint;

    // recipient=>Msg
    mapping(address => Msg[]) public messages;

    constructor(address _lzEndpoint) {
        lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
    }

    // @notice LayerZero endpoint will invoke this function to deliver the message on the destination
    // @param _srcChainId - the source endpoint identifier
    // @param _srcAddress - the source sending contract address from the source chain
    // @param _nonce - the ordered message nonce
    // @param _payload - the signed payload is the UA bytes has encoded to be sent
    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _path,
        uint64 _nonce,
        bytes calldata _payload
    ) external override {
        require(_msgSender() == address(lzEndpoint), "invalid endpoint caller");

        bytes memory path = _path;
        address _srcAddress;
        assembly {
            _srcAddress := mload(add(path, 20))
        }

        _lzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    /// @notice See note on `lzReceive()`
    function _lzReceive(
        uint16 srcChainId,
        address srcAddress,
        uint64 sequence,
        bytes calldata payload
    ) private {
        (address sender, address recipient, string memory message) = abi.decode(
            payload,
            (address, address, string)
        );
        messages[recipient].push(Msg(sender, message));
        emit LzMessageReceived(
            sequence,
            srcChainId,
            srcAddress,
            sender,
            recipient,
            message
        );
    }

    function messagesLength(address recipient) external view returns (uint256) {
        return messages[recipient].length;
    }

    /**
     * @notice set the configuration of the LayerZero messaging library of the specified version
     * @param _version - messaging library version
     * @param _dstChainId - the chainId for the pending config change
     * @param _configType - type of configuration. every messaging library has its own convention.
     * @param _config - configuration in the bytes. can encode arbitrary content.
     */
    function setConfig(
        uint16 _version,
        uint16 _dstChainId,
        uint _configType,
        bytes calldata _config
    ) external onlyOwner {
        lzEndpoint.setConfig(_version, _dstChainId, _configType, _config);
    }

    function setSendVersion(uint16 _version) external onlyOwner {
        lzEndpoint.setSendVersion(_version);
    }

    function setReceiveVersion(uint16 _version) external onlyOwner {
        lzEndpoint.setReceiveVersion(_version);
    }

    function forceResumeReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress
    ) external onlyOwner {
        lzEndpoint.forceResumeReceive(_srcChainId, _srcAddress);
    }

    /// @notice get the send() LayerZero messaging library version
    function getSendVersion() external view returns (uint16) {
        return lzEndpoint.getSendVersion(address(this));
    }

    /**
     * @notice  get the configuration of the LayerZero messaging library of the specified version
     * @param _version - messaging library version
     * @param _dstChainId - the chainId for the pending config change
     * @param _configType - type of configuration. every messaging library has its own convention.
     */
    function getConfig(
        uint16 _version,
        uint16 _dstChainId,
        uint _configType
    ) external view returns (bytes memory) {
        return
            lzEndpoint.getConfig(
                _version,
                _dstChainId,
                address(this),
                _configType
            );
    }
}

