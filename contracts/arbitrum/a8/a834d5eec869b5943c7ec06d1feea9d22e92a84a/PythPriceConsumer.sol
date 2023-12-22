// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./AccessControlEnumerable.sol";
import "./IERC20.sol";
import "./IPriceConsumer.sol";

contract PythStructs {
    struct Price {
        // Price
        int64 price;
        // Confidence interval around the price
        uint64 conf;
        // Price exponent
        int32 expo;
        // Unix timestamp describing when the price was published
        uint256 publishTime;
    }

    // PriceFeed represents a current aggregate price from pyth publisher feeds.
    struct PriceFeed {
        // The price ID.
        bytes32 id;
        // Latest available price
        Price price;
        // Latest available exponentially-weighted moving average price
        Price emaPrice;
    }
}

interface IPyth {
    /// @notice Returns the price of a price feed without any sanity checks.
    /// @dev This function returns the most recent price update in this contract without any recency checks.
    /// This function is unsafe as the returned price update may be arbitrarily far in the past.
    ///
    /// Users of this function should check the `publishTime` in the price to ensure that the returned price is
    /// sufficiently recent for their application. If you are considering using this function, it may be
    /// safer / easier to use either `getPrice` or `getPriceNoOlderThan`.
    /// @return price - please read the documentation of PythStructs.Price to understand how to use this safely.
    function getPriceUnsafe(bytes32 id) external view returns (PythStructs.Price memory price);

    /// @notice Returns true if a price feed with the given id exists.
    /// @param id The Pyth Price Feed ID of which to check its existence.
    function priceFeedExists(bytes32 id) external view returns (bool exists);
}

contract PythPriceConsumer is IPriceConsumer, AccessControlEnumerable {
    IPyth private _pyth;

    bytes32 public constant ORACLE_MANAGER_ROLE = keccak256("ORACLE_MANAGER_ROLE");

    mapping(address => bytes32) private _priceFeedIds;
    mapping(address => uint256) private _tokenPrice;
    mapping(address => uint256) private _tokenTimestamp;

    constructor(address pythContract) {
        _pyth = IPyth(pythContract);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function addPriceFeedInUSD(address token, bytes32 priceFeedId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _priceFeedIds[token] = priceFeedId;
    }

    function fetchPriceInUSD(address token, uint256 minTimestamp) external override onlyRole(ORACLE_MANAGER_ROLE) {
        if (_tokenTimestamp[token] >= minTimestamp) return;
        bytes32 priceId = _priceFeedIds[token];
        if (!_pyth.priceFeedExists(priceId)) {
            return;
        }
        PythStructs.Price memory price = _pyth.getPriceUnsafe(priceId);
        _tokenPrice[token] = price.price >= 0 ? uint256(uint64(price.price)) : 0;
        _tokenTimestamp[token] = price.publishTime;
    }

    function getPriceInUSD(address token) external view override returns (uint256, uint256) {
        return (_tokenPrice[token], _tokenTimestamp[token]);
    }
}

