// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./Admin.sol";

abstract contract VaultStorage is Admin {
    address public implementation;

    bool internal _mutex;

    bool public _paused;

    modifier _reentryLock_() {
        require(!_mutex, "Vault: reentry");
        _mutex = true;
        _;
        _mutex = false;
    }

    modifier _notPaused_() {
        require(!_paused, "Vault: paused");
        _;
    }

    bytes32 public domainSeparator;

    address[] public indexedAssets;

    mapping(address => bool) public supportedAsset;

    uint256 public signatureThreshold;

    address[] public validSigners;

    mapping(address => bool) public isValidSigner;

    mapping(address => uint256) public validatorIndex;

    mapping(bytes32 => bool) public usedHash;

    mapping(address => bool) public isOperator;

    mapping(address => uint256) public debtToMarketVault;
}

