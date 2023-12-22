// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;


import "./ERC20.sol";
import {IBondOracle} from "./IBondOracle.sol";
import {IBondAggregator} from "./IBondAggregator.sol";
import {Owned} from "./Owned.sol";

/// @title Bond Oracle
/// @notice Bond Oracle Base Contract
/// @dev Bond Protocol is a system to create bond markets for any token pair.
///      The markets do not require maintenance and will manage bond prices
///      based on activity. Bond issuers create BondMarkets that pay out
///      a Payout Token in exchange for deposited Quote Tokens. Users can purchase
///      future-dated Payout Tokens with Quote Tokens at the current market price and
///      receive Bond Tokens to represent their position while their bond vests.
///      Once the Bond Tokens vest, they can redeem it for the Quote Tokens.
///
/// @dev Oracles are used by Oracle-based Auctioneers in the Bond system.
///      This base contract implements the IBondOracle interface and provides
///      a starting point for implementing custom Oracle contract.
///      Market creators deploy their own instances of Oracle contracts to
///      control the price feeds used for specific token pairs.
///
/// @author Oighty
abstract contract BondBaseOracle is IBondOracle, Owned {
    /* ========== ERRORS ========== */
    error BondOracle_InvalidParams();
    error BondOracle_NotAuctioneer(address auctioneer);
    error BondOracle_PairNotSupported(ERC20 quoteToken, ERC20 payoutToken);
    error BondOracle_MarketNotRegistered(uint256 id);

    /* ========== EVENTS ========== */
    event PairUpdated(ERC20 quoteToken, ERC20 payoutToken, bool supported);
    event AuctioneerUpdated(address auctioneer, bool supported);
    event MarketRegistered(uint256 id, ERC20 quoteToken, ERC20 payoutToken);

    /* ========== STATE VARIABLES ========== */
    IBondAggregator public immutable aggregator;

    /// @notice Index of market to [quoteToken, payoutToken]
    mapping(uint256 => ERC20[2]) public markets;

    /// @notice Index of supported token pairs (quoteToken => payoutToken => supported)
    mapping(ERC20 => mapping(ERC20 => bool)) public supportedPairs;

    /// @notice Index of supported auctioneers (auctioneer => supported)
    mapping(address => bool) public isAuctioneer;

    /* ========== CONSTRUCTOR ========== */
    constructor(address aggregator_, address[] memory auctioneers_) {
        aggregator = IBondAggregator(aggregator_);

        uint256 len = auctioneers_.length;
        for (uint256 i = 0; i < len; ++i) {
            isAuctioneer[auctioneers_[i]] = true;
        }
    }

    /* ========== REGISTER ========== */
    /// @inheritdoc IBondOracle
    function registerMarket(
        uint256 id_,
        ERC20 quoteToken_,
        ERC20 payoutToken_
    ) external virtual override {
        // Confirm that call is from supported auctioneer
        if (!isAuctioneer[msg.sender]) revert BondOracle_NotAuctioneer(msg.sender);

        // Confirm that the calling auctioneer is the creator of the market ID
        if (address(aggregator.getAuctioneer(id_)) != msg.sender) revert BondOracle_InvalidParams();

        // Confirm that the quote token : payout token pair is supported
        if (!supportedPairs[quoteToken_][payoutToken_])
            revert BondOracle_PairNotSupported(quoteToken_, payoutToken_);

        // Store pair for market ID
        markets[id_] = [quoteToken_, payoutToken_];

        // Emit event
        emit MarketRegistered(id_, quoteToken_, payoutToken_);
    }

    /* ========== PRICE ========== */
    /// @inheritdoc IBondOracle
    function currentPrice(uint256 id_) external view virtual override returns (uint256) {
        // Get tokens for market
        ERC20[2] memory tokens = markets[id_];

        // Check that the market is registered on this oracle
        if (address(tokens[0]) == address(0) || address(tokens[1]) == address(0))
            revert BondOracle_MarketNotRegistered(id_);

        // Get price from oracle
        return _currentPrice(tokens[0], tokens[1]);
    }

    /// @inheritdoc IBondOracle
    function currentPrice(ERC20 quoteToken_, ERC20 payoutToken_)
        external
        view
        virtual
        override
        returns (uint256)
    {
        // Check that the pair is supported by the oracle
        if (
            address(quoteToken_) == address(0) ||
            address(payoutToken_) == address(0) ||
            !supportedPairs[quoteToken_][payoutToken_]
        ) revert BondOracle_PairNotSupported(quoteToken_, payoutToken_);

        // Get price from oracle
        return _currentPrice(quoteToken_, payoutToken_);
    }

    function _currentPrice(ERC20 quoteToken_, ERC20 payoutToken_)
        internal
        view
        virtual
        returns (uint256);

    /* ========== DECIMALS ========== */
    /// @inheritdoc IBondOracle
    function decimals(uint256 id_) external view virtual override returns (uint8) {
        // Get tokens for market
        ERC20[2] memory tokens = markets[id_];

        // Check that the market is registered on this oracle
        if (address(tokens[0]) == address(0) || address(tokens[1]) == address(0))
            revert BondOracle_MarketNotRegistered(id_);

        // Get decimals from oracle
        return _decimals(tokens[0], tokens[1]);
    }

    /// @inheritdoc IBondOracle
    function decimals(ERC20 quoteToken_, ERC20 payoutToken_)
        external
        view
        virtual
        override
        returns (uint8)
    {
        // Check that the pair is supported by the oracle
        if (
            address(quoteToken_) == address(0) ||
            address(payoutToken_) == address(0) ||
            !supportedPairs[quoteToken_][payoutToken_]
        ) revert BondOracle_PairNotSupported(quoteToken_, payoutToken_);

        // Get decimals from oracle
        return _decimals(quoteToken_, payoutToken_);
    }

    function _decimals(ERC20 quoteToken_, ERC20 payoutToken_) internal view virtual returns (uint8);

    /* ========== ADMIN ========== */

    function setAuctioneer(address auctioneer_, bool supported_) external onlyOwner {
        // Check auctioneers current status and revert is not changed to avoid emitting unnecessary events
        if (isAuctioneer[auctioneer_] == supported_) revert BondOracle_InvalidParams();

        // Add/remove auctioneer
        isAuctioneer[auctioneer_] = supported_;

        // Emit event
        emit AuctioneerUpdated(auctioneer_, supported_);
    }

    function setPair(
        ERC20 quoteToken_,
        ERC20 payoutToken_,
        bool supported_,
        bytes calldata oracleData_
    ) external onlyOwner {
        // Don't allow setting tokens to zero address
        if (address(quoteToken_) == address(0) || address(payoutToken_) == address(0))
            revert BondOracle_InvalidParams();

        // Toggle pair status
        supportedPairs[quoteToken_][payoutToken_] = supported_;

        // Update oracle data for particular implementation
        _setPair(quoteToken_, payoutToken_, supported_, oracleData_);

        // Emit event
        emit PairUpdated(quoteToken_, payoutToken_, supported_);
    }

    function _setPair(
        ERC20 quoteToken_,
        ERC20 payoutToken_,
        bool supported_,
        bytes memory oracleData_
    ) internal virtual;
}

