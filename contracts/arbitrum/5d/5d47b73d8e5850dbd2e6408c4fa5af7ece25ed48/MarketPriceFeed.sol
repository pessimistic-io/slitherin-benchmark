// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

import "./AggregatorV2V3Interface.sol";
import "./SafeMath.sol";
import "./SafeCast.sol";
import "./IChainlinkFlags.sol";
import "./IManager.sol";
import "./ISecondaryPriceFeed.sol";
import "./IPriceHelper.sol";

contract MarketPriceFeed {
    using SafeMath for uint256;
    using SafeCast for uint256;

    //uint256 public constant PRICE_DECIMAL = 10;
    uint256 public constant PRICE_PRECISION = 10 ** 10;//price decimal 1e10
    uint256 public constant ONE_USD = PRICE_PRECISION;//1 USD
    uint256 public constant BASIS_POINTS_DIVISOR = 10000;//basis points 1e4
    uint256 public constant MAX_SPREAD_BASIS_POINTS = 50;//max spread basis points 0.5%
    uint256 public constant MAX_ADJUSTMENT_INTERVAL = 2 hours;//max adjustment interval 2 hours，is not allowed to be changed in interval
    uint256 public constant MAX_ADJUSTMENT_BASIS_POINTS = 20;//max adjustment basis points 0.2%

    // Identifier of the Sequencer offline flag on the Flags contract
    address constant private FLAG_ARBITRUM_SEQ_OFFLINE = address(bytes20(bytes32(uint256(keccak256("chainlink.flags.arbitrum-seq-offline")) - 1)));
    address public manager;
    address public chainlinkFlags;//chainlink flags address
    address public priceHelper;//priceHelper address

    bool public isSecondaryPriceEnabled = true; //is offChain price enabled
    uint256 public priceSampleSpace = 1;//price sample space
    uint256 public maxStrictPriceDeviation = 0;//strict stable token price deviation
    address public secondaryPriceFeed; // offChain price feed address

    //token => chainLink address
    mapping(string => address) public priceFeeds;//token => chainLink address
    mapping(string => uint256) public priceDecimals;//token => chainLink price decimal
    mapping(string => uint256) public spreadBasisPoints;//token => spread basis points
    // Chainlink can return prices for stablecoins
    // that differs from 1 USD by a larger percentage than stableSwapFeeBasisPoints
    // we use strictStableTokens to cap the price to 1 USD
    // this allows us to configure stablecoins like DAI as being a stableToken
    // while not being a strictStableToken
    mapping(string => bool) public strictStableTokens;//token => is strict stable token
    mapping(string => uint256) public  adjustmentBasisPoints;//token => adjustment basis points
    mapping(string => bool) public  isAdjustmentAdditive;//token => is adjustment additive
    mapping(string => uint256) public lastAdjustmentTimings;//token => last adjustment timing

    event SetChainlinkFlags(address indexed _chainlinkFlags);
    event SetPriceHelper(address indexed _priceHelper);
    event SetAdjustment(string indexed _token, bool indexed _isAdditive, uint256 indexed _adjustmentBps);
    event SetIsSecondaryPriceEnabled(bool indexed _isEnabled);
    event SetSecondaryPriceFeed(address indexed _secondaryPriceFeed);
    event SetSpreadBasisPoints(string indexed _token, uint256 indexed _spreadBasisPoints);
    event SetPriceSampleSpace(uint256 indexed _priceSampleSpace);
    event SetMaxStrictPriceDeviation(uint256 indexed _maxStrictPriceDeviation);
    event SetTokenConfig(string _token, address _priceFeed, uint256 _priceDecimals, bool _isStrictStable);

    constructor(address _manager) {
        require(_manager != address(0), "MarketPriceFeed: _manager is zero address");
        manager = _manager;
    }

    modifier onlyController() {
        require(IManager(manager).checkController(msg.sender), "MarketPriceFeed: Must be controller");
        _;
    }

    function setChainlinkFlags(address _chainlinkFlags) external onlyController {
        require(_chainlinkFlags != address(0), "MarketPriceFeed: _chainlinkFlags is zero address");
        chainlinkFlags = _chainlinkFlags;
        emit SetChainlinkFlags(_chainlinkFlags);
    }

    function setPriceHelper(address _priceHelper) external onlyController {
        priceHelper = _priceHelper;
        emit SetPriceHelper(_priceHelper);
    }

    function setAdjustment(string memory _token, bool _isAdditive, uint256 _adjustmentBps) external onlyController {
        require(
            lastAdjustmentTimings[_token].add(MAX_ADJUSTMENT_INTERVAL) < block.timestamp,
            "MarketPriceFeed: adjustment frequency exceeded"
        );
        require(_adjustmentBps <= MAX_ADJUSTMENT_BASIS_POINTS, "invalid _adjustmentBps");
        isAdjustmentAdditive[_token] = _isAdditive;
        adjustmentBasisPoints[_token] = _adjustmentBps;
        lastAdjustmentTimings[_token] = block.timestamp;
        emit SetAdjustment(_token, _isAdditive, _adjustmentBps);
    }

    function setIsSecondaryPriceEnabled(bool _isEnabled) external onlyController {
        isSecondaryPriceEnabled = _isEnabled;
        emit SetIsSecondaryPriceEnabled(_isEnabled);
    }

    function setSecondaryPriceFeed(address _secondaryPriceFeed) external onlyController {
        require(_secondaryPriceFeed != address(0), "MarketPriceFeed: _secondaryPriceFeed is zero address");
        secondaryPriceFeed = _secondaryPriceFeed;
        emit SetSecondaryPriceFeed(_secondaryPriceFeed);
    }

    function setSpreadBasisPoints(string memory _token, uint256 _spreadBasisPoints) external onlyController {
        require(_spreadBasisPoints <= MAX_SPREAD_BASIS_POINTS, "MarketPriceFeed: invalid _spreadBasisPoints");
        spreadBasisPoints[_token] = _spreadBasisPoints;
        emit SetSpreadBasisPoints(_token, _spreadBasisPoints);
    }

    function setPriceSampleSpace(uint256 _priceSampleSpace) external onlyController {
        require(_priceSampleSpace > 0, "MarketPriceFeed: invalid _priceSampleSpace");
        priceSampleSpace = _priceSampleSpace;
        emit SetPriceSampleSpace(_priceSampleSpace);
    }

    function setMaxStrictPriceDeviation(uint256 _maxStrictPriceDeviation) external onlyController {
        maxStrictPriceDeviation = _maxStrictPriceDeviation;
        emit SetMaxStrictPriceDeviation(_maxStrictPriceDeviation);
    }

    function setTokenConfig(
        string memory _token,
        address _priceFeed,
        uint256 _priceDecimals,
        bool _isStrictStable
    ) external onlyController {
        priceFeeds[_token] = _priceFeed;
        priceDecimals[_token] = _priceDecimals;
        strictStableTokens[_token] = _isStrictStable;
        emit SetTokenConfig(_token, _priceFeed, _priceDecimals, _isStrictStable);
    }

    function getPrice(string memory _token, uint256 value, uint256 maxValue, bool _maximise) public view returns (uint256) {
        uint256 price = getPriceV1(_token, _maximise);
        uint256 adjustmentBps = adjustmentBasisPoints[_token];
        if (adjustmentBps > 0) {
            bool isAdditive = isAdjustmentAdditive[_token];
            if (isAdditive) {
                price = price.mul(BASIS_POINTS_DIVISOR.add(adjustmentBps)).div(BASIS_POINTS_DIVISOR);
            } else {
                price = price.mul(BASIS_POINTS_DIVISOR.sub(adjustmentBps)).div(BASIS_POINTS_DIVISOR);
            }
        }
        
        if (priceHelper != address(0)) {
            price = IPriceHelper(priceHelper).getSlipPointPrice(_token, price, value, maxValue, _maximise);
        }

        return price;
    }

    function getPriceV1(string memory _token, bool _maximise) public view returns (uint256) {
        uint256 price = getPrimaryPrice(_token, _maximise);

        if (isSecondaryPriceEnabled) {
            price = getSecondaryPrice(_token, price, _maximise);
        }


        if (strictStableTokens[_token]) {
            uint256 delta = price > ONE_USD ? price.sub(ONE_USD) : ONE_USD.sub(price);
            if (delta <= maxStrictPriceDeviation) {
                return ONE_USD;
            }

            // if _maximise and price is e.g. 1.02, return 1.02
            if (_maximise && price > ONE_USD) {
                return price;
            }

            // if !_maximise and price is e.g. 0.98, return 0.98
            if (!_maximise && price < ONE_USD) {
                return price;
            }

            return ONE_USD;
        }

        uint256 _spreadBasisPoints = spreadBasisPoints[_token];

        if (_maximise) {
            return price.mul(BASIS_POINTS_DIVISOR.add(_spreadBasisPoints)).div(BASIS_POINTS_DIVISOR);
        }
        return price.mul(BASIS_POINTS_DIVISOR.sub(_spreadBasisPoints)).div(BASIS_POINTS_DIVISOR);
    }

    function getLatestPrimaryPrice(string memory _token) public view returns (uint256) {
        address priceFeedAddress = priceFeeds[_token];
        require(priceFeedAddress != address(0), "MarketPriceFeed: invalid price feed");

        AggregatorV2V3Interface priceFeed = AggregatorV2V3Interface(priceFeedAddress);

        int256 price = priceFeed.latestAnswer();
        require(price > 0, "MarketPriceFeed: invalid price");

        return uint256(price).mul(PRICE_PRECISION).div(10 ** priceFeed.decimals());
    }

    function getPrimaryPrice(string memory _token, bool _maximise) public view returns (uint256) {
        address priceFeedAddress = priceFeeds[_token];
        require(priceFeedAddress != address(0), "MarketPriceFeed: invalid price feed");

        AggregatorV2V3Interface priceFeed = AggregatorV2V3Interface(priceFeedAddress);
        uint256 price = 0;
        uint256 roundId = priceFeed.latestRound();
        for (uint80 i = 0; i < priceSampleSpace; i++) {
            if (roundId <= i) {break;}
            uint256 p;

            if (i == 0) {
                int256 _p = priceFeed.latestAnswer();
                require(_p > 0, "MarketPriceFeed: invalid price");
                p = uint256(_p);
            } else {
                (, int256 _p, , ,) = priceFeed.getRoundData((roundId - i).toUint80());
                require(_p > 0, "MarketPriceFeed: invalid price");
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

        require(price > 0, "MarketPriceFeed: could not fetch price");
        // normalise price precision
        uint256 _priceDecimals = priceDecimals[_token];
        return price.mul(PRICE_PRECISION).div(10 ** _priceDecimals);
    }

    function getSecondaryPrice(string memory _token, uint256 _referencePrice, bool _maximise) public view returns (uint256) {
        if (secondaryPriceFeed == address(0)) {return _referencePrice;}
        return ISecondaryPriceFeed(secondaryPriceFeed).getPrice(_token, _referencePrice, _maximise);
    }

    function getIndexPrice(string memory _token, bool _maximise) internal view returns (uint256) {
        return ISecondaryPriceFeed(secondaryPriceFeed).getIndexPrice(_token, getLatestPrimaryPrice(_token), _maximise);
    }

    function priceForTrade(string memory _token, uint256 value, uint256 maxValue, bool _maximise) external view returns (uint256){
        return getPrice(_token, value, maxValue, _maximise);
    }

    function priceForPool(string memory _token, bool _maximise) external view returns (uint256){
        return getIndexPrice(_token, _maximise);
    }

    function priceForLiquidate(string memory _token, bool _maximise) external view returns (uint256){
        return getIndexPrice(_token, _maximise);
    }

    function priceForIndex(string memory _token, bool _maximise) external view returns (uint256){
        return getIndexPrice(_token, _maximise);
    }
}

