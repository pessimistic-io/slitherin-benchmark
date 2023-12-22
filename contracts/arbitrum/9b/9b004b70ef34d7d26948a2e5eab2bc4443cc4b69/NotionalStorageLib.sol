//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./ContangoVault.sol";
import "./NotionalUtils.sol";

import "./StorageLib.sol";

library NotionalStorageLib {
    using NotionalUtils for ERC20;
    using SafeCast for uint256;

    NotionalProxy internal constant NOTIONAL = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);

    /// @dev Storage IDs for storage buckets. Each id maps to an internal storage
    /// slot used for a particular mapping
    ///     WARNING: APPEND ONLY
    enum NotionalStorageId {
        Unused, // 0
        Instruments, // 1
        Vaults // 2
    }

    error InvalidBaseId(Symbol symbol, uint16 currencyId);
    error InvalidQuoteId(Symbol symbol, uint16 currencyId);
    error InvalidMarketIndex(uint16 currencyId, uint256 marketIndex, uint256 max);
    error MismatchedMaturity(Symbol symbol, uint16 baseId, uint32 baseMaturity, uint16 quoteId, uint32 quoteMaturity);

    event NotionalInstrumentCreated(
        InstrumentStorage instrument, NotionalInstrumentStorage notionalInstrument, ContangoVault vault
    );

    // solhint-disable no-inline-assembly
    function getVaults() internal pure returns (mapping(Symbol => ContangoVault) storage store) {
        uint256 slot = getStorageSlot(NotionalStorageId.Vaults);
        assembly {
            store.slot := slot
        }
    }
    // solhint-enable no-inline-assembly

    // solhint-disable no-inline-assembly
    /// @dev Mapping from a symbol to instrument
    function getInstruments() internal pure returns (mapping(Symbol => NotionalInstrumentStorage) storage store) {
        uint256 slot = getStorageSlot(NotionalStorageId.Instruments);
        assembly {
            store.slot := slot
        }
    }
    // solhint-enable no-inline-assembly

    function getInstrument(PositionId positionId) internal view returns (NotionalInstrumentStorage storage) {
        return getInstruments()[StorageLib.getPositionInstrument()[positionId]];
    }

    function createInstrument(
        Symbol symbol,
        uint16 baseId,
        uint16 quoteId,
        uint256 marketIndex,
        ContangoVault vault,
        address weth // sucks but beats doing another SLOAD to fetch from configs
    ) internal returns (InstrumentStorage memory instrument, NotionalInstrumentStorage memory notionalInstrument) {
        uint32 maturity = _validInstrumentData(symbol, baseId, quoteId, marketIndex);
        (instrument, notionalInstrument) = _createInstrument(baseId, quoteId, maturity, weth);

        // since the contango contracts should not hold any funds once a transaction is done,
        // and createInstrument is a permissioned manually invoked admin function (therefore with controlled inputs),
        // infinite approve here to the vault is fine
        SafeTransferLib.safeApprove(ERC20(address(instrument.base)), address(vault), type(uint256).max);
        SafeTransferLib.safeApprove(ERC20(address(instrument.quote)), address(vault), type(uint256).max);

        StorageLib.getInstruments()[symbol] = instrument;
        getInstruments()[symbol] = notionalInstrument;
        getVaults()[symbol] = vault;

        emit NotionalInstrumentCreated(instrument, notionalInstrument, vault);
    }

    function _createInstrument(uint16 baseId, uint16 quoteId, uint32 maturity, address weth)
        private
        view
        returns (InstrumentStorage memory instrument, NotionalInstrumentStorage memory notionalInstrument)
    {
        notionalInstrument.baseId = baseId;
        notionalInstrument.quoteId = quoteId;

        instrument.maturity = maturity;

        (, Token memory baseUnderlyingToken) = NOTIONAL.getCurrency(baseId);
        (, Token memory quoteUnderlyingToken) = NOTIONAL.getCurrency(quoteId);

        address baseAddress = baseUnderlyingToken.tokenType == TokenType.Ether ? weth : baseUnderlyingToken.tokenAddress;
        address quoteAddress =
            quoteUnderlyingToken.tokenType == TokenType.Ether ? weth : quoteUnderlyingToken.tokenAddress;

        instrument.base = ERC20(baseAddress);
        instrument.quote = ERC20(quoteAddress);

        notionalInstrument.basePrecision = (10 ** instrument.base.decimals()).toUint64();
        notionalInstrument.quotePrecision = (10 ** instrument.quote.decimals()).toUint64();

        notionalInstrument.isQuoteWeth = address(instrument.quote) == address(weth);
    }

    /// @dev Get the storage slot given a storage ID.
    /// @param storageId An entry in `NotionalStorageId`
    /// @return slot The storage slot.
    function getStorageSlot(NotionalStorageId storageId) internal pure returns (uint256 slot) {
        return uint256(storageId) + NOTIONAL_STORAGE_SLOT_BASE;
    }

    function _validInstrumentData(Symbol symbol, uint16 baseId, uint16 quoteId, uint256 marketIndex)
        private
        view
        returns (uint32)
    {
        if (StorageLib.getInstruments()[symbol].maturity != 0) {
            revert InstrumentAlreadyExists(symbol);
        }

        // should never happen in Notional since it validates that the currencyId is valid and has a valid maturity
        uint256 baseMaturity = _validateMarket(NOTIONAL, baseId, marketIndex);
        if (baseMaturity == 0 || baseMaturity > type(uint32).max) {
            revert InvalidBaseId(symbol, baseId);
        }

        // should never happen in Notional since it validates that the currencyId is valid and has a valid maturity
        uint256 quoteMaturity = _validateMarket(NOTIONAL, quoteId, marketIndex);
        if (quoteMaturity == 0 || quoteMaturity > type(uint32).max) {
            revert InvalidQuoteId(symbol, quoteId);
        }

        // should never happen since we're using the exact marketIndex on the same block/timestamp
        if (baseMaturity != quoteMaturity) {
            revert MismatchedMaturity(symbol, baseId, uint32(baseMaturity), quoteId, uint32(quoteMaturity));
        }

        return uint32(baseMaturity);
    }

    function _validateMarket(NotionalProxy notional, uint16 currencyId, uint256 marketIndex)
        private
        view
        returns (uint256 maturity)
    {
        MarketParameters[] memory marketParameters = notional.getActiveMarkets(currencyId);
        if (marketIndex == 0 || marketIndex > marketParameters.length) {
            revert InvalidMarketIndex(currencyId, marketIndex, marketParameters.length);
        }

        maturity = marketParameters[marketIndex - 1].maturity;
    }
}

