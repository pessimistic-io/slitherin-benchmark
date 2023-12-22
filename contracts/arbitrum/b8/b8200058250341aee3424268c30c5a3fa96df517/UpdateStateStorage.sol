// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./Admin.sol";

abstract contract UpdateStateStorage is Admin {

    address public implementation;

    bool internal _mutex;

    modifier _reentryLock_() {
        require(!_mutex, "update: reentry");
        _mutex = true;
        _;
        _mutex = false;
    }

    uint256 public lastUpdateTimestamp;

    uint256 public lastBatchId;

    uint256 public lastEndTimestamp;

    bool public isFreezed;

    bool public isFreezeStart;

    uint256 public freezeStartTimestamp;

    modifier _notFreezed() {
        require(!isFreezed, "update: freezed");
        _;
    }

    modifier _onlyOperator() {
        require(isOperator[msg.sender], "update: only operator");
        _;
    }

    struct SymbolInfo {
        string symbolName;
        bytes32 symbolId;
        uint256 minVolume;
        uint256 pricePrecision;
        uint256 volumePrecision;
        address marginAsset;
        bool delisted;
    }

    struct SymbolStats {
        int64 indexPrice;
        int64 cumulativeFundingPerVolume;
    }

    struct AccountPosition {
        int64 volume;
        int64 lastCumulativeFundingPerVolume;
        int128 entryCost;
    }

    mapping(address => bool) public isOperator;

    // indexed symbols for looping
    SymbolInfo[] public indexedSymbols;

    // symbolId => symbolInfo
    mapping (bytes32 => SymbolInfo) public symbols;

    // symbolId => symbolStats
    mapping(bytes32 => SymbolStats) public symbolStats;

    // user => asset => balance
    mapping(address => mapping(address => int256)) public balances;

    // account => symbolId => AccountPosition
    mapping(address => mapping(bytes32 => AccountPosition)) public accountPositions;

    // account => hold position #
    mapping(address => int256) public holdPositions;

}

