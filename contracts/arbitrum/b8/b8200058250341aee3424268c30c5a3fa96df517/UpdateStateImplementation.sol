// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./SafeERC20.sol";
import "./NameVersion.sol";
import "./Log.sol";
import "./UpdateStateStorage.sol";
import "./UpdateState.sol";
import "./ForcedAction.sol";


contract UpdateStateImplementation is ForcedAction, NameVersion {
    using Log for *;
    using SafeERC20 for IERC20;

    // shift the 1s by (256 - 64) to get (256 - 64) 0s followed by 64 1s
    uint256 constant public PRICE_BITMASK = type(uint256).max >> (256 - 64);

    uint256 constant public FREEZE_LIMIT = 7 days;

    uint256 constant public GRACE_PERIOD = 7 days;

    event SetOperator(address operator, bool isActive);

    event AddSymbol(
        string symbolName,
        bytes32 symbolId,
        uint256 minVolume,
        uint256 priceDecimals,
        uint256 volumeDecimals,
        address marginAsset
    );

    event UpdateSymbol(
        string symbolName,
        bytes32 symbolId,
        uint256 minVolume,
        uint256 priceDecimals,
        uint256 volumeDecimals,
        address marginAsset
    );

    event DelistSymbol(
        string symbolName,
        bytes32 symbolId
    );


    constructor(address _vault) ForcedAction(_vault) NameVersion('UpdateState', '1.0.0') {}

    // ========================================================
    // Admin Functions
    // ========================================================
    function setOperator(address operator_, bool isActive) external _onlyAdmin_ {
        isOperator[operator_] = isActive;
        emit SetOperator(operator_, isActive);
    }

    // ========================================================
    // External Calls For Vault
    // ========================================================
    function updateBalance(address account, address asset, int256 balanceDiff) external {
        require(msg.sender == address(vault), "update: not vault");
        balances[account][asset] += balanceDiff;
        emit LogBalanceChange(account, asset, balanceDiff);
    }

    function updatePosition(uint256[] calldata positionInput) external {
        require(msg.sender == address(vault), "update: not vault");
        _updateAccountPosition(positionInput);
    }

    function resetFreezeStart() external {
        require(msg.sender == address(vault), "update: not vault");
        if (isFreezeStart) isFreezeStart = false;
    }


    // ========================================================
    // Symbol Management
    // ========================================================
    function addSymbol(string calldata _symbolName, uint256 _minVolume, uint256 _pricePrecision, uint256 _volumePrecision, address _marginAsset) external _onlyOperator {
        bytes32 _symbolId = keccak256(abi.encodePacked(_symbolName));
        require(symbols[_symbolId].symbolId == bytes32(0), "update: addSymbol already exist");
        SymbolInfo memory symbolInfo = SymbolInfo({
            symbolName: _symbolName,
            symbolId: _symbolId,
            minVolume: _minVolume,
            pricePrecision: _pricePrecision,
            volumePrecision: _volumePrecision,
            marginAsset: _marginAsset,
            delisted: false
        });
        symbols[_symbolId] = symbolInfo;
        indexedSymbols.push(symbolInfo);

        emit AddSymbol(
            _symbolName,
            _symbolId,
            _minVolume,
            _pricePrecision,
            _volumePrecision,
            _marginAsset
        );
    }

    function updateSymbol(string calldata _symbolName, uint256 _minVolume, uint256 _pricePrecision, uint256 _volumePrecision, address _marginAsset) external _onlyOperator {
        bytes32 _symbolId = keccak256(abi.encodePacked(_symbolName));
        require(symbols[_symbolId].symbolId != bytes32(0), "update: updateSymbol not exist");
        SymbolInfo memory symbolInfo = SymbolInfo({
            symbolName: _symbolName,
            symbolId: _symbolId,
            minVolume: _minVolume,
            pricePrecision: _pricePrecision,
            volumePrecision: _volumePrecision,
            marginAsset: _marginAsset,
            delisted: false
        });
        symbols[_symbolId] = symbolInfo;
        emit UpdateSymbol(
            _symbolName,
            _symbolId,
            _minVolume,
            _pricePrecision,
            _volumePrecision,
            _marginAsset
        );
    }


    function delistSymbol(bytes32 symbolId) external _onlyOperator {
        require(symbols[symbolId].minVolume != 0 && !symbols[symbolId].delisted, "update: symbol not exist or delisted");
        symbols[symbolId].delisted = true;
        emit DelistSymbol(
            symbols[symbolId].symbolName,
            symbolId
        );
    }


    // ========================================================
    // Forced Functions
    // ========================================================
    function requestFreeze() _notFreezed external {
        uint256 duration = block.timestamp - lastUpdateTimestamp;
        require(duration > FREEZE_LIMIT, "update: last update time less than freeze limit");
        isFreezeStart = true;
        freezeStartTimestamp = block.timestamp;
    }

    function activateFreeze() _notFreezed external {
        require(isFreezeStart, "update: freeze request not started");
        uint256 duration = block.timestamp - freezeStartTimestamp;
        require(duration > GRACE_PERIOD, "update: freeze time did not past grace period");
        isFreezed = true;
    }



    // ========================================================
    // batch update
    // ========================================================
    function batchUpdate(
        uint256[] calldata priceInput,
        uint256[] calldata fundingInput,
        int256[] calldata balanceInput,
        uint256[] calldata positionInput,
        uint256 batchId,
        uint256 endTimestamp
    ) external _notFreezed _onlyOperator {
        require(isOperator[msg.sender], "update: operator only");
        require(lastBatchId == batchId - 1, "update: invalid batch id");

        if (isFreezeStart) isFreezeStart = false;

        _updateSymbols(priceInput, fundingInput);
        _updateAccountBalance(balanceInput);
        _updateAccountPosition(positionInput);

        lastBatchId += 1;
        lastUpdateTimestamp = block.timestamp;
        lastEndTimestamp = endTimestamp;
    }


    function _updateSymbols(
        uint256[] calldata _indexPrices,
        uint256[] calldata _cumulativeFundingPerVolumes
    ) internal {
        require(_indexPrices.length == _cumulativeFundingPerVolumes.length, "update: invalid length");

        for (uint256 i = 0; i < _indexPrices.length; i++) {
            uint256 indexPrice = _indexPrices[i];
            uint256 cumulativeFundingPerVolume = _cumulativeFundingPerVolumes[i];
            for (uint256 j = 0; j < 4; j++) {
                uint256 index = i * 4 + j;
                if (index >= indexedSymbols.length) { return; }
                uint256 startBit = 64 * j;
                int256 _indexPrice = int256((indexPrice >> startBit) & PRICE_BITMASK);
                if (_indexPrice == 0) continue;
                int256 _cumulativeFundingPerVolume = int256((cumulativeFundingPerVolume >> startBit) & PRICE_BITMASK);
                bytes32 symbolId = indexedSymbols[index].symbolId;
                symbolStats[symbolId] = SymbolStats({
                    indexPrice: int64(_indexPrice),
                    cumulativeFundingPerVolume: int64(_cumulativeFundingPerVolume)
                });
                }
        }
    }


    function _updateAccountBalance(int256[] calldata balanceInput) internal {
        require(balanceInput.length % 3 == 0, "update: invalid balanceInput length");
        uint256 nUpdates = balanceInput.length / 3;
        uint256 offset = 0;
        for (uint256 i = 0; i < nUpdates; i++) {
            address account = address(uint160(uint256(balanceInput[offset])));
            address asset = address(uint160(uint256(balanceInput[offset + 1])));
            int256 balanceDiff = balanceInput[offset + 2];

            balances[account][asset] += balanceDiff;
            emit LogBalanceChange(account, asset, balanceDiff);
            offset += 3;
        }
    }

    function _updateAccountPosition(uint256[] calldata positionInput) internal {
        require(positionInput.length % 3 == 0, "update: invalid positionInput length");
        uint256 nUpdates = positionInput.length / 3;
        uint256 offset = 0;
        for (uint256 i = 0; i < nUpdates; i++) {
            address account = address(uint160(uint256(positionInput[offset])));
            bytes32 symbolId = bytes32(uint256(positionInput[offset + 1]));
            uint256 positionStat = positionInput[offset + 2];

            int256 _volume = int256(positionStat & ((1 << 64) - 1));
            int256 _lastCumulativeFundingPerVolume = int256((positionStat >> 64) & ((1 << 128) - 1));
            int256 _entryCost = int256((positionStat >> 128) & ((1 << 128) - 1));

            if (accountPositions[account][symbolId].volume == 0 && _volume != 0) {
                holdPositions[account] += 1;
            } else if (accountPositions[account][symbolId].volume != 0 && _volume == 0) {
                holdPositions[account] -= 1;
            }
            accountPositions[account][symbolId] = AccountPosition({
                    volume: int64(_volume),
                    lastCumulativeFundingPerVolume: int64(_lastCumulativeFundingPerVolume),
                    entryCost: int128(_entryCost)
                });
            emit LogPositionChange(account, symbolId, int64(_volume), int64(_lastCumulativeFundingPerVolume), int128(_entryCost));
            offset += 3;
        }
    }

    function getSymbolNum() external view returns(uint256) {
        return indexedSymbols.length;
    }

    function getSymbolNames(uint256 start, uint256 end) external view returns (string[] memory) {
        string[] memory symbolNames = new string[](end - start);
        for (uint256 i = start; i < end; i++) {
            symbolNames[i] = indexedSymbols[i].symbolName;
        }
        return symbolNames;
    }

}

