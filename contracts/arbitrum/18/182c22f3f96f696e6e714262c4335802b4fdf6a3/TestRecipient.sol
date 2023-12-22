// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

import {Ownable} from "./Ownable.sol";

interface IMessageRecipient {
    function handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _message
    ) external;
}

interface IInterchainSecurityModule {
    enum Types {
        NULL, // used with relayer carrying no metadata
        ROUTING,
        AGGREGATION,
        LEGACY_MULTISIG,
        MERKLE_ROOT_MULTISIG,
        MESSAGE_ID_MULTISIG,
        OPTIMISM
    }

    /**
     * @notice Returns an enum that represents the type of security model
     * encoded by this ISM.
     * @dev Relayers infer how to fetch and format metadata.
     */
    function moduleType() external view returns (uint8);

    /**
     * @notice Defines a security model responsible for verifying interchain
     * messages based on the provided metadata.
     * @param _metadata Off-chain metadata provided by a relayer, specific to
     * the security model encoded by the module (e.g. validator signatures)
     * @param _message Hyperlane encoded interchain message
     * @return True if the message was verified
     */
    function verify(bytes calldata _metadata, bytes calldata _message)
        external
        returns (bool);
}

interface ISpecifiesInterchainSecurityModule {
    function interchainSecurityModule()
        external
        view
        returns (IInterchainSecurityModule);
}

contract TestRecipient is
    Ownable,
    IMessageRecipient,
    ISpecifiesInterchainSecurityModule
{
    IInterchainSecurityModule public interchainSecurityModule;
    bytes32 public lastSender;
    bytes public lastData;

    address public lastCaller;
    string public lastCallMessage;

    event ReceivedMessage(
        uint32 indexed origin,
        bytes32 indexed sender,
        string message
    );

    event ReceivedCall(address indexed caller, uint256 amount, string message);

    function handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _data
    ) external virtual override {
        emit ReceivedMessage(_origin, _sender, string(_data));
        lastSender = _sender;
        lastData = _data;
    }

    function fooBar(uint256 amount, string calldata message) external {
        emit ReceivedCall(msg.sender, amount, message);
        lastCaller = msg.sender;
        lastCallMessage = message;
    }

    function setInterchainSecurityModule(address _ism) external onlyOwner {
        interchainSecurityModule = IInterchainSecurityModule(_ism);
    }
}

