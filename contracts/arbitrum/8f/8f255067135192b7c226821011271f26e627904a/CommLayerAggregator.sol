//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Counters.sol";
import "./Ownable.sol";
import "./ICommLayer.sol";

contract CommLayerAggregator is Ownable {
    using Counters for Counters.Counter;

    address public fetcchBridge;

    /// @notice Counter to keep track of supported Communication Layers
    Counters.Counter private _commLayerIds;

    mapping(uint256 => address) public commLayerId;

    error OnlyFetcchBridge();

    constructor(address _fetcchBridge) {
        fetcchBridge = _fetcchBridge;
    }

    /// @notice This function is responsible for adding new communication layer to aggregator
    /// @dev onlyOwner is allowed to call this function
    /// @param _newCommLayer Address of new communication layer
    function setCommLayer(address _newCommLayer) external onlyOwner {
        _commLayerIds.increment();
        uint256 commId = _commLayerIds.current();
        commLayerId[commId] = _newCommLayer;
    }

    /// @notice This function returns address of communication layer corresponding to its id
    /// @param _id Id of the communication layer
    function getCommLayer(uint256 _id) external view returns (address) {
        return commLayerId[_id];
    }

    /// @notice This function is responsible for sending messages to another chain
    /// @dev It makes call to corresponding commLayer depending on commLayerId
    /// @param _id Id of communication layer
    /// @param _payload Address of destination contract to send message on
    /// @param _extraParams Encoded extra parameters
    function sendMsg(
        uint256 _id,
        bytes calldata _payload,
        bytes calldata _extraParams
    ) public payable {
        if (msg.sender != fetcchBridge) revert OnlyFetcchBridge();
        ICommLayer(commLayerId[_id]).sendMsg{value: msg.value}(
            _payload,
            _extraParams
        );
    }
}

