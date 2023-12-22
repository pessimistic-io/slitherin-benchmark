//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IAxelarGateway} from "./IAxelarGateway.sol";
import {IAxelarGasService} from "./IAxelarGasService.sol";
import {AxelarExecutable} from "./AxelarExecutable.sol";
import "./AccessControl.sol";
import "./ICommLayer.sol";
import "./IBridge.sol";

contract AxelarImpl is AxelarExecutable, AccessControl, ICommLayer {
    /// @notice Axelar gas service address
    IAxelarGasService public gasReceiver;

    /// @notice Communication layer aggregator addresses
    ICommLayer public commLayerAggregator;

    IBridge public fetcchBridge;

    bytes32 public constant SOURCE = keccak256("SOURCE");

    event MsgSent(string _dstChain, string _destination, bytes _payload);

    event Executed(string sourceChain, string sourceAddress, bytes _payload);

    mapping(string => string) private destination;

    error OnlyGateway();
    error InvalidSource();

    /// @dev Initializes the contract by setting gateway, gasReceiver and commLayerAggregator address
    constructor(
        address _gateway,
        address _gasReceiver,
        address _commLayerAggregator,
        address _fetcchBridge
    ) AxelarExecutable(_gateway) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        gasReceiver = IAxelarGasService(_gasReceiver);
        commLayerAggregator = ICommLayer(_commLayerAggregator);
        fetcchBridge = IBridge(_fetcchBridge);
    }

    modifier onlyCommLayerAggregator() {
        require(msg.sender == address(commLayerAggregator));
        _;
    }

    /// @notice This function is responsible for setting source Axelar addresses
    /// @dev onlyOwner is allowed to call this function
    /// @param _source Source chain Axelar address
    function setSource(
        string calldata _destinationChain,
        string calldata _source
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(SOURCE, address(bytes20(bytes(_source))));
        destination[_destinationChain] = _source;
    }

    /// @notice This function is responsible for changing commLayerAggregator address
    /// @dev onlyOwner can call this function
    /// @param _aggregator New communication layer aggregator address
    function changeCommLayerAggregator(
        address _aggregator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        commLayerAggregator = ICommLayer(_aggregator);
    }

    /// @notice This function is responsible for changing gasReceiver address
    /// @dev onlyOwner can call this function
    /// @param _gasReceiver New gas receiver address
    function changeGasReceiver(
        address _gasReceiver
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        gasReceiver = IAxelarGasService(_gasReceiver);
    }

    /// @notice This function is responsible for sending messages to another chain using LayerZero
    /// @dev It makes call to LayerZero endpoint contract
    /// @dev This function can only be called from CommLayerAggregator
    /// @param payload Encoded data to send on destination chain
    /// @param extraParams Encoded extra parameters
    function sendMsg(
        bytes memory payload,
        bytes memory extraParams
    ) external payable onlyCommLayerAggregator {
        string memory destinationChain = abi.decode(extraParams, (string));
        if (msg.value > 0) {
            gasReceiver.payNativeGasForContractCall{value: msg.value}(
                address(this),
                destinationChain,
                destination[destinationChain],
                payload,
                msg.sender
            );
        }
        gateway.callContract(
            destinationChain,
            destination[destinationChain],
            payload
        );
        emit MsgSent(destinationChain, destination[destinationChain], payload);
    }

    /// @notice This function is responsible for receiving messages
    /// @dev This function is directly called by Axelar gateway
    function _execute(
        string memory sourceChain,
        string memory sourceAddress,
        bytes calldata payload
    ) internal override {
        if (!hasRole(SOURCE, address(bytes20(bytes(sourceAddress)))))
            revert InvalidSource();

        (address tokenOut, uint256 amount, address receiver) = abi.decode(
            payload,
            (address, uint256, address)
        );
        fetcchBridge.release(tokenOut, amount, receiver);

        emit Executed(sourceChain, sourceAddress, payload);
    }

    function _toAsciiString(address x) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(
                uint8(uint256(uint160(x)) / (2 ** (8 * (19 - i))))
            );
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i] = _char(hi);
            s[2 * i + 1] = _char(lo);
        }
        return string(s);
    }

    function _char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
}

