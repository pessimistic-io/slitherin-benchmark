// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IMarketHistory.sol";
import "./AccessHandler.sol";
// For debugging only


/**
 * @title Market History
 * @author Deepp Dev Team
 * @notice Simple contract for historical market data.
 * @notice This is a sub contract for the Bookie app.
 * @notice Accesshandler is Initializable.
 */
contract MarketHistory is IMarketHistory, AccessHandler {





    // market hash => market state
    mapping(bytes32 => MarketState) private marketStates;
    // market hash => market outcome
    mapping(bytes32 => MarketOutcome) private marketOutcomes;

    /**
     * @notice Event that fires when a market is added.
     * @param marketHash is the hash used to identify the market.
     */
    event MarketAdded(bytes32 indexed marketHash);

    /**
     * @notice Event that fires when a market is playing.
     * @param marketHash is the hash used to identify the market.
     */
    event MarketPlaying(bytes32 indexed marketHash);

    /**
     * @notice Event that fires when a market is settled.
     * @param marketHash is the hash used to identify the market.
     * @param outcome is the outcome of the market.
     */
    event MarketSettled(
        bytes32 indexed marketHash,
        IMarketHistory.MarketOutcome outcome
    );

    /**
     * @notice Error when trying to add a market that already exists.
     * @param marketHash is the hash of the existing market.
     */
    error DuplicateMarket(bytes32 marketHash);

    /**
     * @notice Error when trying to access a market that has the wrong state.
     * @param expected is the expected state of the requested market.
     * @param current is the actual state of the requested market.
     */
    error InvalidMarketState(
        IMarketHistory.MarketState expected,
        IMarketHistory.MarketState current
    );

    /**
     * @notice Simple constructor that just initizializes.
     */
    constructor() {
        BaseInitializer.initialize();
    }

















    /**
     * @notice Adds a market, based on a hash.
     * @notice Error is emitted if the market already exists, Event if not.
     */
    function addMarket(bytes32 hash)
        public
        override
        isInitialized
        onlyRole(REPORTER_ROLE)
    {
        // Checks that it does not exist already
        IMarketHistory.MarketState existingMarketState = marketStates[hash];
        if (existingMarketState != IMarketHistory.MarketState.Undefined)
            revert DuplicateMarket({marketHash: hash});

        marketStates[hash] = IMarketHistory.MarketState.Active;
        marketOutcomes[hash] = IMarketHistory.MarketOutcome.Undefined;

        emit MarketAdded(hash);
    }

    /**
     * @notice Updates a market to Playing state.
     * @notice Revert Error is emitted if not exist.
     * @param marketHash is the hash of the market to update.
     */
    function setMarketPlaying(bytes32 marketHash)
        external
        override
        onlyRole(REPORTER_ROLE)
    {
        // Checks that it is active
        if (marketStates[marketHash] != IMarketHistory.MarketState.Active) {
            revert InvalidMarketState({
                expected: IMarketHistory.MarketState.Active,
                current: marketStates[marketHash]
            });
        }
        marketStates[marketHash] = IMarketHistory.MarketState.Playing;
        emit MarketPlaying(marketHash);
    }

    /**
     * @notice Updates a market to Settled state.
     * @notice Revert Error is emitted if not exist or invalid.
     * @param marketHash is the hash of the market to update.
     * @param outcome is the outcome of market, eg Win, loss etc.
     */
    function settleMarket(bytes32 marketHash, IMarketHistory.MarketOutcome outcome)
        external
        override
        onlyRole(REPORTER_ROLE)
    {
        // Checks that it is Active
        if (marketStates[marketHash] != IMarketHistory.MarketState.Playing) {
            revert InvalidMarketState({
                expected: IMarketHistory.MarketState.Playing,
                current: marketStates[marketHash]
            });
        }
        marketStates[marketHash] = IMarketHistory.MarketState.Completed;
        marketOutcomes[marketHash] = outcome;
        emit MarketSettled(marketHash, outcome);
    }

    /**
     * @notice Check if market exists and is active.
     * @notice Errors are emitted if check fails.
     * @param marketHash is the hash of the market to check.
     */
    function assertMarketIsActive(bytes32 marketHash) external view override {
        IMarketHistory.MarketState state = marketStates[marketHash];
        if (state != IMarketHistory.MarketState.Active) {
            revert InvalidMarketState({
                expected: IMarketHistory.MarketState.Active,
                current: state
            });
        }
    }

    /**
     * @notice Check if market exists and is completed.
     * @notice Errors are emitted if check fails.
     * @param marketHash is the hash of the market to check.
     */
    function assertMarketIsCompleted(bytes32 marketHash) external view override {
        IMarketHistory.MarketState state = marketStates[marketHash];
        if (state != IMarketHistory.MarketState.Completed) {
            revert InvalidMarketState({
                expected: IMarketHistory.MarketState.Completed,
                current: state
            });
        }
    }

    /**
     * @notice Check if a market has a specific outcome.
     * @param marketHash is the hash of the market to check.
     * @param outcome is the outcome to compare with.
     * @return bool is TRUE if they match, FALSE if not.
     */
    function isMarketOutcome(
        bytes32 marketHash,
        IMarketHistory.MarketOutcome outcome
    )
        external
        view
        override
        returns (bool)
    {
        if (marketOutcomes[marketHash] == outcome)
            return true;
        return false;
    }

    /**
     * @notice Get a market state.
     * @param marketHash is the hash of the market to find.
     * @return IMarketHistory.MarketState is the state of the supplied market.
     */
    function getMarketState(bytes32 marketHash)
        external
        view
        override
        returns (IMarketHistory.MarketState)
    {
        return marketStates[marketHash];
    }
}

