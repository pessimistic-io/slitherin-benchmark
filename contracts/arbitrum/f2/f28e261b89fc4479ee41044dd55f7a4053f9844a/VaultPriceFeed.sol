// SPDX-License-Identifier: MIT

import "./H2SOFA.sol";
import "./AggregatorV2V3Interface.sol";
import "./SafeMath.sol";
import "./IVaultPriceFeed.sol";
import "./ISecondaryPriceFeed.sol";
import "./IChainlinkFlags.sol";
import "./IPancakePair.sol";

pragma solidity 0.6.12;

contract VaultPriceFeed is IVaultPriceFeed {
    using SafeMath for uint256;

    uint256 public constant PRICE_PRECISION = 10**30;
    uint256 public constant ONE_USD = PRICE_PRECISION;
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;
    uint256 public constant MAX_SPREAD_BASIS_POINTS = 50;
    uint256 public constant MAX_ADJUSTMENT_INTERVAL = 2 hours;
    uint256 public constant MAX_ADJUSTMENT_BASIS_POINTS = 20;

    // Identifier of the Sequencer offline flag on the Flags contract
    address private constant FLAG_ARBITRUM_SEQ_OFFLINE =
        address(
            bytes20(
                bytes32(
                    uint256(keccak256("chainlink.flags.arbitrum-seq-offline")) -
                        1
                )
            )
        );

    address public gov;
    address public chainlinkFlags;

    bool public isAmmEnabled = true;
    bool public isSecondaryPriceEnabled = true;
    bool public useV2Pricing = false;
    bool public favorPrimaryPrice = false;
    uint256 public priceSampleSpace = 1;
    uint256 public maxStrictPriceDeviation = 0;
    address public secondaryPriceFeed;
    uint256 public spreadThresholdBasisPoints = 30;
    /// @notice Defines how old the current value for a price feed is allowed to be.
    uint256 public h2soQuoteLifetimeSeconds = 0;

    address public btc;
    address public eth;
    address public bnb;
    address public bnbBusd;
    address public ethBnb;
    address public btcBnb;

    mapping(address => address) public priceFeeds;
    mapping(address => uint256) public priceDecimals;
    mapping(address => uint256) public spreadBasisPoints;
    // Chainlink can return prices for stablecoins
    // that differs from 1 USD by a larger percentage than stableSwapFeeBasisPoints
    // we use strictStableTokens to cap the price to 1 USD
    // this allows us to configure stablecoins like DAI as being a stableToken
    // while not being a strictStableToken
    mapping(address => bool) public strictStableTokens;

    mapping(address => uint256) public override adjustmentBasisPoints;
    mapping(address => bool) public override isAdjustmentAdditive;
    mapping(address => uint256) public lastAdjustmentTimings;

    modifier onlyGov() {
        require(msg.sender == gov, "VaultPriceFeed: forbidden");
        _;
    }

    constructor() public {
        gov = msg.sender;
    }

    function setGov(address _gov) external onlyGov {
        gov = _gov;
    }

    function setH2soQuoteLifetimeSeconds(uint256 value)
        external
        override
        onlyGov
    {
        require(h2soQuoteLifetimeSeconds != value, "Already set");
        h2soQuoteLifetimeSeconds = value;
    }

    function setChainlinkFlags(address _chainlinkFlags) external onlyGov {
        chainlinkFlags = _chainlinkFlags;
    }

    function setAdjustment(
        address _token,
        bool _isAdditive,
        uint256 _adjustmentBps
    ) external override onlyGov {
        require(
            lastAdjustmentTimings[_token].add(MAX_ADJUSTMENT_INTERVAL) <
                block.timestamp,
            "VaultPriceFeed: adjustment frequency exceeded"
        );
        require(
            _adjustmentBps <= MAX_ADJUSTMENT_BASIS_POINTS,
            "invalid _adjustmentBps"
        );
        isAdjustmentAdditive[_token] = _isAdditive;
        adjustmentBasisPoints[_token] = _adjustmentBps;
        lastAdjustmentTimings[_token] = block.timestamp;
    }

    function setUseV2Pricing(bool _useV2Pricing) external override onlyGov {
        useV2Pricing = _useV2Pricing;
    }

    function setIsAmmEnabled(bool _isEnabled) external override onlyGov {
        isAmmEnabled = _isEnabled;
    }

    function setIsSecondaryPriceEnabled(bool _isEnabled)
        external
        override
        onlyGov
    {
        isSecondaryPriceEnabled = _isEnabled;
    }

    function setSecondaryPriceFeed(address _secondaryPriceFeed)
        external
        onlyGov
    {
        secondaryPriceFeed = _secondaryPriceFeed;
    }

    function setTokens(
        address _btc,
        address _eth,
        address _bnb
    ) external onlyGov {
        btc = _btc;
        eth = _eth;
        bnb = _bnb;
    }

    function setPairs(
        address _bnbBusd,
        address _ethBnb,
        address _btcBnb
    ) external onlyGov {
        bnbBusd = _bnbBusd;
        ethBnb = _ethBnb;
        btcBnb = _btcBnb;
    }

    function setSpreadBasisPoints(address _token, uint256 _spreadBasisPoints)
        external
        override
        onlyGov
    {
        require(
            _spreadBasisPoints <= MAX_SPREAD_BASIS_POINTS,
            "VaultPriceFeed: invalid _spreadBasisPoints"
        );
        spreadBasisPoints[_token] = _spreadBasisPoints;
    }

    function setSpreadThresholdBasisPoints(uint256 _spreadThresholdBasisPoints)
        external
        override
        onlyGov
    {
        spreadThresholdBasisPoints = _spreadThresholdBasisPoints;
    }

    function setFavorPrimaryPrice(bool _favorPrimaryPrice)
        external
        override
        onlyGov
    {
        favorPrimaryPrice = _favorPrimaryPrice;
    }

    function setPriceSampleSpace(uint256 _priceSampleSpace)
        external
        override
        onlyGov
    {
        require(
            _priceSampleSpace > 0,
            "VaultPriceFeed: invalid _priceSampleSpace"
        );
        priceSampleSpace = _priceSampleSpace;
    }

    function setMaxStrictPriceDeviation(uint256 _maxStrictPriceDeviation)
        external
        override
        onlyGov
    {
        maxStrictPriceDeviation = _maxStrictPriceDeviation;
    }

    function setTokenConfig(
        address _token,
        address _priceFeed,
        uint256 _priceDecimals,
        bool _isStrictStable
    ) external override onlyGov {
        priceFeeds[_token] = _priceFeed;
        priceDecimals[_token] = _priceDecimals;
        strictStableTokens[_token] = _isStrictStable;
    }

    /**
     * @notice Applies a signed quote to the underlying H2SO implementation.
     * @dev Uses a an abi encoded input to reduce stack size from calling side.
     */
    function h2sofaApplySignedQuote(bytes calldata signedQuoteData)
        external
        override
    {
        uint256 quoteCount;
        address[] memory tokenAddresses = new address[](quoteCount);
        uint256[] memory values = new uint256[](quoteCount);
        uint256[] memory signedTimestamps = new uint256[](quoteCount);
        uint256[] memory validFromTimestamps = new uint256[](quoteCount);
        uint256[] memory durationSeconds = new uint256[](quoteCount);
        // 65 byte signatures contiguously stored within a bytes array.
        bytes memory signatures65;
        (
            quoteCount,
            tokenAddresses,
            values,
            signedTimestamps,
            validFromTimestamps,
            durationSeconds,
            signatures65
        ) = abi.decode(
            signedQuoteData,
            (
                uint256,
                address[],
                uint256[],
                uint256[],
                uint256[],
                uint256[],
                bytes
            )
        );
        // Signature array length must be divisible by 65.
        assert(signatures65.length % 65 == 0);
        // Signature array length divided by 65 must be equal to quote count.
        assert(signatures65.length / 65 == quoteCount);
        for (uint256 i = 0; i < quoteCount; i++) {
            uint256 offset = i * 65;
            bytes memory signature = new bytes(65);
            for (uint256 j = 0; j < 65; j++) {
                signature[j] = signatures65[j + offset];
            }
            H2SOFA h2sofa = H2SOFA(priceFeeds[tokenAddresses[i]]);
            // The function call will fail if the configured price feed
            // does not support the H2SOFA interface.
            try
                h2sofa.submitWithQuote(
                    values[i],
                    signedTimestamps[i],
                    validFromTimestamps[i],
                    durationSeconds[i],
                    signature
                )
            {} catch Error(string memory reason) {
                // If the quote is old, continue with the transaction.
                // This means the transaction will use the existing price.
                // If the existing price is expired (due to the quote lifetime),
                // then the transaction will revert when fetching the price.
                bytes32 hash = keccak256(abi.encode(reason));
                bytes32 bypassHash = keccak256(
                    abi.encode("H2SO: Quote is old")
                );
                require(hash == bypassHash, reason);
            }
        }
    }

    function getPrice(
        address _token,
        bool _maximise,
        bool _includeAmmPrice,
        bool /* _useSwapPricing */
    ) public view override returns (uint256) {
        uint256 price = useV2Pricing
            ? getPriceV2(_token, _maximise, _includeAmmPrice)
            : getPriceV1(_token, _maximise, _includeAmmPrice);

        uint256 adjustmentBps = adjustmentBasisPoints[_token];
        if (adjustmentBps > 0) {
            bool isAdditive = isAdjustmentAdditive[_token];
            if (isAdditive) {
                price = price.mul(BASIS_POINTS_DIVISOR.add(adjustmentBps)).div(
                    BASIS_POINTS_DIVISOR
                );
            } else {
                price = price.mul(BASIS_POINTS_DIVISOR.sub(adjustmentBps)).div(
                    BASIS_POINTS_DIVISOR
                );
            }
        }

        return price;
    }

    function getPriceV1(
        address _token,
        bool _maximise,
        bool _includeAmmPrice
    ) public view returns (uint256) {
        uint256 price = getPrimaryPrice(_token, _maximise);

        if (_includeAmmPrice && isAmmEnabled) {
            uint256 ammPrice = getAmmPrice(_token);
            if (ammPrice > 0) {
                if (_maximise && ammPrice > price) {
                    price = ammPrice;
                }
                if (!_maximise && ammPrice < price) {
                    price = ammPrice;
                }
            }
        }

        if (isSecondaryPriceEnabled) {
            price = getSecondaryPrice(_token, price, _maximise);
        }

        if (strictStableTokens[_token]) {
            uint256 delta = price > ONE_USD
                ? price.sub(ONE_USD)
                : ONE_USD.sub(price);
            if (delta <= maxStrictPriceDeviation) {
                return ONE_USD;
            }
        }

        uint256 _spreadBasisPoints = spreadBasisPoints[_token];

        if (_maximise) {
            return
                price.mul(BASIS_POINTS_DIVISOR.add(_spreadBasisPoints)).div(
                    BASIS_POINTS_DIVISOR
                );
        }

        return
            price.mul(BASIS_POINTS_DIVISOR.sub(_spreadBasisPoints)).div(
                BASIS_POINTS_DIVISOR
            );
    }

    function getPriceV2(
        address _token,
        bool _maximise,
        bool _includeAmmPrice
    ) public view returns (uint256) {
        uint256 price = getPrimaryPrice(_token, _maximise);

        if (_includeAmmPrice && isAmmEnabled) {
            price = getAmmPriceV2(_token, _maximise, price);
        }

        if (isSecondaryPriceEnabled) {
            price = getSecondaryPrice(_token, price, _maximise);
        }

        if (strictStableTokens[_token]) {
            uint256 delta = price > ONE_USD
                ? price.sub(ONE_USD)
                : ONE_USD.sub(price);
            if (delta <= maxStrictPriceDeviation) {
                return ONE_USD;
            }
        }

        uint256 _spreadBasisPoints = spreadBasisPoints[_token];

        if (_maximise) {
            return
                price.mul(BASIS_POINTS_DIVISOR.add(_spreadBasisPoints)).div(
                    BASIS_POINTS_DIVISOR
                );
        }

        return
            price.mul(BASIS_POINTS_DIVISOR.sub(_spreadBasisPoints)).div(
                BASIS_POINTS_DIVISOR
            );
    }

    function getAmmPriceV2(
        address _token,
        bool _maximise,
        uint256 _primaryPrice
    ) public view returns (uint256) {
        uint256 ammPrice = getAmmPrice(_token);
        if (ammPrice == 0) {
            return _primaryPrice;
        }

        uint256 diff = ammPrice > _primaryPrice
            ? ammPrice.sub(_primaryPrice)
            : _primaryPrice.sub(ammPrice);
        if (
            diff.mul(BASIS_POINTS_DIVISOR) <
            _primaryPrice.mul(spreadThresholdBasisPoints)
        ) {
            if (favorPrimaryPrice) {
                return _primaryPrice;
            }
            return ammPrice;
        }

        if (_maximise && ammPrice > _primaryPrice) {
            return ammPrice;
        }

        if (!_maximise && ammPrice < _primaryPrice) {
            return ammPrice;
        }

        return _primaryPrice;
    }

    function getPrimaryPrice(address _token, bool _maximise)
        public
        view
        override
        returns (uint256)
    {
        address priceFeedAddress = priceFeeds[_token];
        require(
            priceFeedAddress != address(0),
            "VaultPriceFeed: invalid price feed"
        );

        if (chainlinkFlags != address(0)) {
            bool isRaised = IChainlinkFlags(chainlinkFlags).getFlag(
                FLAG_ARBITRUM_SEQ_OFFLINE
            );
            if (isRaised) {
                // If flag is raised we shouldn't perform any critical operations
                revert("Chainlink feeds are not being updated");
            }
        }

        AggregatorV2V3Interface priceFeed = AggregatorV2V3Interface(
            priceFeedAddress
        );

        uint256 price = 0;
        (uint80 roundId, int256 latestAnswer, , uint256 updatedAt, ) = priceFeed
            .latestRoundData();

        require(
            block.timestamp <= updatedAt + h2soQuoteLifetimeSeconds,
            "VaultPriceFeed: Must submit new price"
        );

        for (uint80 i = 0; i < priceSampleSpace; i++) {
            if (roundId <= i) {
                break;
            }
            uint256 p;

            if (i == 0) {
                int256 _p = latestAnswer;
                require(_p > 0, "VaultPriceFeed: invalid price");
                p = uint256(_p);
            } else {
                (, int256 _p, , , ) = priceFeed.getRoundData(roundId - i);
                require(_p > 0, "VaultPriceFeed: invalid price");
                p = uint256(_p);
            }

            if (price == 0) {
                price = p;
                continue;
            }

            if (_maximise && p > price) {
                price = p;
                continue;
            }

            if (!_maximise && p < price) {
                price = p;
            }
        }

        require(price > 0, "VaultPriceFeed: could not fetch price");
        // normalise price precision
        uint256 _priceDecimals = priceDecimals[_token];
        return price.mul(PRICE_PRECISION).div(10**_priceDecimals);
    }

    function getSecondaryPrice(
        address _token,
        uint256 _referencePrice,
        bool _maximise
    ) public view returns (uint256) {
        if (secondaryPriceFeed == address(0)) {
            return _referencePrice;
        }
        return
            ISecondaryPriceFeed(secondaryPriceFeed).getPrice(
                _token,
                _referencePrice,
                _maximise
            );
    }

    function getAmmPrice(address _token)
        public
        view
        override
        returns (uint256)
    {
        if (_token == bnb) {
            // for bnbBusd, reserve0: BNB, reserve1: BUSD
            return getPairPrice(bnbBusd, true);
        }

        if (_token == eth) {
            uint256 price0 = getPairPrice(bnbBusd, true);
            // for ethBnb, reserve0: ETH, reserve1: BNB
            uint256 price1 = getPairPrice(ethBnb, true);
            // this calculation could overflow if (price0 / 10**30) * (price1 / 10**30) is more than 10**17
            return price0.mul(price1).div(PRICE_PRECISION);
        }

        if (_token == btc) {
            uint256 price0 = getPairPrice(bnbBusd, true);
            // for btcBnb, reserve0: BTC, reserve1: BNB
            uint256 price1 = getPairPrice(btcBnb, true);
            // this calculation could overflow if (price0 / 10**30) * (price1 / 10**30) is more than 10**17
            return price0.mul(price1).div(PRICE_PRECISION);
        }

        return 0;
    }

    // if divByReserve0: calculate price as reserve1 / reserve0
    // if !divByReserve1: calculate price as reserve0 / reserve1
    function getPairPrice(address _pair, bool _divByReserve0)
        public
        view
        returns (uint256)
    {
        (uint256 reserve0, uint256 reserve1, ) = IPancakePair(_pair)
            .getReserves();
        if (_divByReserve0) {
            if (reserve0 == 0) {
                return 0;
            }
            return reserve1.mul(PRICE_PRECISION).div(reserve0);
        }
        if (reserve1 == 0) {
            return 0;
        }
        return reserve0.mul(PRICE_PRECISION).div(reserve1);
    }
}

