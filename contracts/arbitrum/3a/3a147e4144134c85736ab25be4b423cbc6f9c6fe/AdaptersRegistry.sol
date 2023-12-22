// SPDX-License-Identifier: MIT



pragma solidity 0.8.19;

import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";

import {IAdaptersRegistry} from "./IAdaptersRegistry.sol";

contract AdaptersRegistry is OwnableUpgradeable, IAdaptersRegistry {
    mapping(uint256 => address) private _adapters;

    uint256[] public validProtocols;

    uint256 public nextProtocolId;

    function initialize() external initializer {
        __Ownable_init();

        nextProtocolId = 1;
    }

    function getAdapterAddress(
        uint256 _protocolId
    ) external view returns (bool adapterExists, address adapter) {
        adapter = _adapters[_protocolId];
        adapterExists = adapter != address(0);
    }

    function allValidProtocols() external view returns (uint256[] memory) {
        return validProtocols;
    }

    function addAdapterAddress(
        address _adapter
    ) external onlyOwner {
        if (_adapter == address(0)) revert ZeroAddress({target: "_adapterAddress"});
        
        uint256 _nextProtocolId = nextProtocolId++;
        _adapters[_nextProtocolId] = _adapter;
        validProtocols.push(_nextProtocolId);
        emit AdapterAdded(_adapter);
    }
}

