// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IGNSTradingStorage.sol";

import "./StorageUtils.sol";

/**
 * @custom:version 6.4.2
 *
 * @dev This is a library to help manage a price impact decay algorithm .
 *
 * When a trade is placed, OI is added to the window corresponding to time of open.
 * When a trade is removed, OI is removed from the window corresponding to time of open.
 *
 * When calculating price impact, only the most recent X windows are taken into account.
 */
library PriceImpactUtils {
    uint256 private constant PRECISION = 1e10; // 10 decimals

    uint48 private constant MAX_WINDOWS_COUNT = 5;
    uint48 private constant MAX_WINDOWS_DURATION = 1 days;
    uint48 private constant MIN_WINDOWS_DURATION = 10 minutes;

    struct OiWindowsStorage {
        OiWindowsSettings settings;
        mapping(uint48 => mapping(uint256 => mapping(uint256 => PairOi))) windows; // duration => pairIndex => windowId => Oi
    }

    struct OiWindowsSettings {
        uint48 startTs;
        uint48 windowsDuration;
        uint48 windowsCount;
    }

    struct PairOi {
        uint128 long; // 1e18 (DAI)
        uint128 short; // 1e18 (DAI)
    }

    struct OiWindowUpdate {
        uint48 windowsDuration;
        uint256 pairIndex;
        uint256 windowId;
        bool long;
        uint128 openInterest; // 1e18 (DAI)
    }

    /**
     * @dev Triggered when OiWindowsSettings is initialized (once)
     */
    event OiWindowsSettingsInitialized(uint48 indexed windowsDuration);

    /**
     * @dev Triggered when OiWindowsSettings.windowsCount is updated
     */
    event PriceImpactWindowsCountUpdated(uint48 indexed windowsCount);

    /**
     * @dev Triggered when OiWindowsSettings.windowsDuration is updated
     */
    event PriceImpactWindowsDurationUpdated(uint48 indexed windowsDuration);

    /**
     * @dev Triggered when OI is added to a window.
     */
    event PriceImpactOpenInterestAdded(OiWindowUpdate oiWindowUpdate);

    /**
     * @dev Triggered when OI is (tentatively) removed from a window.
     */
    event PriceImpactOpenInterestRemoved(OiWindowUpdate oiWindowUpdate, bool notOutdated);

    /**
     * @dev Triggered when multiple pairs' OI are transferred to a new window.
     */
    event PriceImpactOiTransferredPairs(
        uint256 pairsCount,
        uint256 prevCurrentWindowId,
        uint256 prevEarliestWindowId,
        uint256 newCurrentWindowId
    );

    /**
     * @dev Triggered when a pair's OI is transferred to a new window.
     */
    event PriceImpactOiTransferredPair(uint256 indexed pairIndex, PairOi totalPairOi);

    /**
     * @dev Returns storage pointer for struct in borrowing contract, at defined slot
     */
    function getStorage() private pure returns (OiWindowsStorage storage s) {
        uint256 storageSlot = StorageUtils.PRICE_IMPACT_OI_WINDOWS_STORAGE_SLOT;
        assembly {
            s.slot := storageSlot
        }
    }

    /**
     * @dev Validates new windowsDuration value
     */
    modifier validWindowsDuration(uint48 _windowsDuration) {
        require(
            _windowsDuration >= MIN_WINDOWS_DURATION && _windowsDuration <= MAX_WINDOWS_DURATION,
            "WRONG_WINDOWS_DURATION"
        );
        _;
    }

    /**
     * @dev Initializes OiWindowsSettings startTs and windowsDuration.
     * windowsCount is 0 for now for backwards-compatible behavior until oi windows have enough data.
     *
     * Should only be called once, in initializeV2() of borrowing contract.
     * Emits a {OiWindowsSettingsInitialized} event.
     */
    function initializeOiWindowsSettings(uint48 _windowsDuration) external validWindowsDuration(_windowsDuration) {
        getStorage().settings = OiWindowsSettings({
            startTs: uint48(block.timestamp),
            windowsDuration: _windowsDuration,
            windowsCount: 0 // maintains previous price impact OI behavior for now
        });

        emit OiWindowsSettingsInitialized(_windowsDuration);
    }

    /**
     * @dev Updates OiWindowSettings.windowsCount storage value
     *
     * Emits a {PriceImpactWindowsCountUpdated} event.
     */
    function setPriceImpactWindowsCount(uint48 _newWindowsCount) external {
        OiWindowsSettings storage settings = getStorage().settings;

        require(_newWindowsCount <= MAX_WINDOWS_COUNT, "ABOVE_MAX_WINDOWS_COUNT");
        require(_newWindowsCount == 0 || getCurrentWindowId(settings) >= _newWindowsCount - 1, "TOO_EARLY");

        settings.windowsCount = _newWindowsCount;

        emit PriceImpactWindowsCountUpdated(_newWindowsCount);
    }

    /**
     * @dev Updates OiWindowSettings.windowsDuration storage value,
     * and transfers the OI from all pairs past active windows (current window duration)
     * to the new current window (new window duration).
     *
     * Emits a {PriceImpactWindowsDurationUpdated} event.
     */
    function setPriceImpactWindowsDuration(
        uint48 _newWindowsDuration,
        uint256 _pairsCount
    ) external validWindowsDuration(_newWindowsDuration) {
        OiWindowsStorage storage oiStorage = getStorage();
        OiWindowsSettings storage settings = oiStorage.settings;

        if (settings.windowsCount > 0) {
            transferPriceImpactOiForPairs(
                _pairsCount,
                oiStorage.windows[settings.windowsDuration],
                oiStorage.windows[_newWindowsDuration],
                settings,
                _newWindowsDuration
            );
        }

        settings.windowsDuration = _newWindowsDuration;

        emit PriceImpactWindowsDurationUpdated(_newWindowsDuration);
    }

    /**
     * @dev Adds long / short `_openInterest` (1e18) to current window of `_pairIndex`.
     *
     * Emits a {PriceImpactOpenInterestAdded} event.
     */
    function addPriceImpactOpenInterest(uint128 _openInterest, uint256 _pairIndex, bool _long) external {
        OiWindowsStorage storage oiStorage = getStorage();
        OiWindowsSettings storage settings = oiStorage.settings;

        uint256 currentWindowId = getCurrentWindowId(settings);
        PairOi storage pairOi = oiStorage.windows[settings.windowsDuration][_pairIndex][currentWindowId];

        if (_long) {
            pairOi.long += _openInterest;
        } else {
            pairOi.short += _openInterest;
        }

        emit PriceImpactOpenInterestAdded(
            OiWindowUpdate(settings.windowsDuration, _pairIndex, currentWindowId, _long, _openInterest)
        );
    }

    /**
     * @dev Removes `_openInterest` (1e18) from window at `_addTs` of `_pairIndex`.
     *
     * Emits a {PriceImpactOpenInterestRemoved} event when `_addTs` is greater than zero.
     */
    function removePriceImpactOpenInterest(
        uint128 _openInterest,
        uint256 _pairIndex,
        bool _long,
        uint48 _addTs
    ) external {
        // If trade opened before update, OI wasn't stored in any window anyway
        if (_addTs == 0) {
            return;
        }

        OiWindowsStorage storage oiStorage = getStorage();
        OiWindowsSettings storage settings = oiStorage.settings;

        uint256 currentWindowId = getCurrentWindowId(settings);
        uint256 addWindowId = getWindowId(_addTs, settings);

        bool notOutdated = isWindowPotentiallyActive(addWindowId, currentWindowId);

        // Only remove OI if window is not outdated already
        if (notOutdated) {
            PairOi storage pairOi = oiStorage.windows[settings.windowsDuration][_pairIndex][addWindowId];

            if (_long) {
                pairOi.long = _openInterest < pairOi.long ? pairOi.long - _openInterest : 0;
            } else {
                pairOi.short = _openInterest < pairOi.short ? pairOi.short - _openInterest : 0;
            }
        }

        emit PriceImpactOpenInterestRemoved(
            OiWindowUpdate(settings.windowsDuration, _pairIndex, addWindowId, _long, _openInterest),
            notOutdated
        );
    }

    /**
     * @dev Transfers total long / short OI from last '_settings.windowsCount' windows of `_prevPairOiWindows`
     * to current window of `_newPairOiWindows` for `pairsCount` pairs.
     *
     * Emits a {PriceImpactOiTransferredPairs} event.
     */
    function transferPriceImpactOiForPairs(
        uint256 pairsCount,
        mapping(uint256 => mapping(uint256 => PairOi)) storage _prevPairOiWindows, // pairIndex => windowId => PairOi
        mapping(uint256 => mapping(uint256 => PairOi)) storage _newPairOiWindows, // pairIndex => windowId => PairOi
        OiWindowsSettings memory _settings,
        uint48 _newWindowsDuration
    ) private {
        uint256 prevCurrentWindowId = getCurrentWindowId(_settings);
        uint256 prevEarliestWindowId = getEarliestActiveWindowId(prevCurrentWindowId, _settings.windowsCount);

        uint256 newCurrentWindowId = getCurrentWindowId(
            OiWindowsSettings(_settings.startTs, _newWindowsDuration, _settings.windowsCount)
        );

        for (uint256 pairIndex; pairIndex < pairsCount; ) {
            transferPriceImpactOiForPair(
                pairIndex,
                prevCurrentWindowId,
                prevEarliestWindowId,
                _prevPairOiWindows[pairIndex],
                _newPairOiWindows[pairIndex][newCurrentWindowId]
            );

            unchecked {
                ++pairIndex;
            }
        }

        emit PriceImpactOiTransferredPairs(pairsCount, prevCurrentWindowId, prevEarliestWindowId, newCurrentWindowId);
    }

    /**
     * @dev Transfers total long / short OI from `prevEarliestWindowId` to `prevCurrentWindowId` windows of
     * `_prevPairOiWindows` to `_newPairOiWindow` window.
     *
     * Emits a {PriceImpactOiTransferredPair} event.
     */
    function transferPriceImpactOiForPair(
        uint256 pairIndex,
        uint256 prevCurrentWindowId,
        uint256 prevEarliestWindowId,
        mapping(uint256 => PairOi) storage _prevPairOiWindows,
        PairOi storage _newPairOiWindow
    ) private {
        PairOi memory totalPairOi;

        // Aggregate sum of total long / short OI for past windows
        for (uint256 id = prevEarliestWindowId; id <= prevCurrentWindowId; ) {
            PairOi memory pairOi = _prevPairOiWindows[id];

            totalPairOi.long += pairOi.long;
            totalPairOi.short += pairOi.short;

            // Clean up previous map once added to the sum
            delete _prevPairOiWindows[id];

            unchecked {
                ++id;
            }
        }

        bool longOiTransfer = totalPairOi.long > 0;
        bool shortOiTransfer = totalPairOi.short > 0;

        if (longOiTransfer) {
            _newPairOiWindow.long += totalPairOi.long;
        }

        if (shortOiTransfer) {
            _newPairOiWindow.short += totalPairOi.short;
        }

        // Only emit even if there was an actual OI transfer
        if (longOiTransfer || shortOiTransfer) {
            emit PriceImpactOiTransferredPair(pairIndex, totalPairOi);
        }
    }

    /**
     * @dev Returns window id at `_timestamp` given `_settings`.
     */
    function getWindowId(uint48 _timestamp, OiWindowsSettings memory _settings) internal pure returns (uint256) {
        return (_timestamp - _settings.startTs) / _settings.windowsDuration;
    }

    /**
     * @dev Returns window id at current timestamp given `_settings`.
     */
    function getCurrentWindowId(OiWindowsSettings memory _settings) internal view returns (uint256) {
        return getWindowId(uint48(block.timestamp), _settings);
    }

    /**
     * @dev Returns earliest active window id given `_currentWindowId` and `_windowsCount`.
     */
    function getEarliestActiveWindowId(uint256 _currentWindowId, uint48 _windowsCount) internal pure returns (uint256) {
        uint256 windowNegativeDelta = _windowsCount - 1; // -1 because we include current window
        return _currentWindowId > windowNegativeDelta ? _currentWindowId - windowNegativeDelta : 0;
    }

    /**
     * @dev Returns whether '_windowId' can be potentially active id given `_currentWindowId`
     */
    function isWindowPotentiallyActive(uint256 _windowId, uint256 _currentWindowId) internal pure returns (bool) {
        return _currentWindowId - _windowId < MAX_WINDOWS_COUNT;
    }

    /**
     * @dev Returns total long / short OI `activeOi`, from last active windows of `_pairOiWindows`
     * given `_settings` (backwards-compatible).
     */
    function getPriceImpactOi(
        uint256 _pairIndex,
        bool _long,
        IGNSTradingStorage _previousOiContract
    ) external view returns (uint256 activeOi) {
        OiWindowsStorage storage oiStorage = getStorage();
        OiWindowsSettings storage settings = oiStorage.settings;

        // Return raw OI if windowsCount is explicitly 0 (= previous behavior)
        if (settings.windowsCount == 0) {
            return _previousOiContract.openInterestDai(_pairIndex, _long ? 0 : 1);
        }

        uint256 currentWindowId = getCurrentWindowId(settings);
        uint256 earliestWindowId = getEarliestActiveWindowId(currentWindowId, settings.windowsCount);

        for (uint256 i = earliestWindowId; i <= currentWindowId; ) {
            PairOi memory _pairOi = oiStorage.windows[settings.windowsDuration][_pairIndex][i];
            activeOi += _long ? _pairOi.long : _pairOi.short;

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Returns trade price impact % and opening price after impact.
     */
    function getTradePriceImpact(
        uint256 _openPrice, // PRECISION
        bool _long,
        uint256 _startOpenInterest, // 1e18 (DAI)
        uint256 _tradeOpenInterest, // 1e18 (DAI)
        uint256 _onePercentDepth
    )
        external
        pure
        returns (
            uint256 priceImpactP, // PRECISION (%)
            uint256 priceAfterImpact // PRECISION
        )
    {
        if (_onePercentDepth == 0) {
            return (0, _openPrice);
        }

        priceImpactP = ((_startOpenInterest + _tradeOpenInterest / 2) * PRECISION) / _onePercentDepth / 1e18;

        uint256 priceImpact = (priceImpactP * _openPrice) / PRECISION / 100;
        priceAfterImpact = _long ? _openPrice + priceImpact : _openPrice - priceImpact;
    }
}

