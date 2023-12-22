// SPDX-License-Identifier: MIT

import "./SafeMath.sol";

import "./ISecondaryPriceFeed.sol";
import "./IFastPriceEvents.sol";
import "./Governable.sol";

pragma solidity 0.6.12;

contract FastPriceFeed is ISecondaryPriceFeed, Governable {
    using SafeMath for uint256;

    uint256 public constant PRICE_PRECISION = 10 ** 30;

    // uint256(~0) is 256 bits of 1s
    // shift the 1s by (256 - 32) to get (256 - 32) 0s followed by 32 1s
    uint256 constant public PRICE_BITMASK = uint256(~0) >> (256 - 32);

    bool public isInitialized;
    bool public isSpreadEnabled = false;
    address public fastPriceEvents;

    address public admin;
    address public tokenManager;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    uint256 public constant MAX_PRICE_DURATION = 30 minutes;

    uint256 public lastUpdatedAt;
    uint256 public priceDuration;

    // volatility basis points
    uint256 public volBasisPoints;
    // max deviation from primary price
    uint256 public maxDeviationBasisPoints;

    mapping (address => uint256) public prices;

    uint256 public minAuthorizations;
    uint256 public disableFastPriceVoteCount = 0;
    mapping (address => bool) public isSigner;
    mapping (address => bool) public disableFastPriceVotes;

    // array of tokens used in setCompactedPrices, saves L1 calldata gas costs
    address[] public tokens;
    // array of tokenPrecisions used in setCompactedPrices, saves L1 calldata gas costs
    // if the token price will be sent with 3 decimals, then tokenPrecision for that token
    // should be 10 ** 3
    uint256[] public tokenPrecisions;

    modifier onlySigner() {
        require(isSigner[msg.sender], "FastPriceFeed: forbidden");
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "FastPriceFeed: forbidden");
        _;
    }

    modifier onlyTokenManager() {
        require(msg.sender == tokenManager, "FastPriceFeed: forbidden");
        _;
    }

    constructor(
      uint256 _priceDuration,
      uint256 _maxDeviationBasisPoints,
      address _fastPriceEvents,
      address _admin,
      address _tokenManager
    ) public {
        require(_priceDuration <= MAX_PRICE_DURATION, "FastPriceFeed: invalid _priceDuration");
        priceDuration = _priceDuration;
        maxDeviationBasisPoints = _maxDeviationBasisPoints;
        fastPriceEvents = _fastPriceEvents;
        admin = _admin;
        tokenManager = _tokenManager;
    }

    function initialize(uint256 _minAuthorizations, address[] memory _signers) public onlyGov {
        require(!isInitialized, "FastPriceFeed: already initialized");
        isInitialized = true;

        minAuthorizations = _minAuthorizations;

        for (uint256 i = 0; i < _signers.length; i++) {
            address signer = _signers[i];
            isSigner[signer] = true;
        }
    }

    function setAdmin(address _admin) external onlyTokenManager {
        admin = _admin;
    }

    function setFastPriceEvents(address _fastPriceEvents) external onlyGov {
      fastPriceEvents = _fastPriceEvents;
    }

    function setPriceDuration(uint256 _priceDuration) external onlyGov {
        require(_priceDuration <= MAX_PRICE_DURATION, "FastPriceFeed: invalid _priceDuration");
        priceDuration = _priceDuration;
    }

    function setIsSpreadEnabled(bool _isSpreadEnabled) external onlyGov {
        isSpreadEnabled = _isSpreadEnabled;
    }

    function setVolBasisPoints(uint256 _volBasisPoints) external onlyGov {
        volBasisPoints = _volBasisPoints;
    }

    function setTokens(address[] memory _tokens, uint256[] memory _tokenPrecisions) external onlyGov {
        require(_tokens.length == _tokenPrecisions.length, "FastPriceFeed: invalid lengths");
        tokens = _tokens;
        tokenPrecisions = _tokenPrecisions;
    }

    function setPrices(address[] memory _tokens, uint256[] memory _prices) external onlyAdmin {
        for (uint256 i = 0; i < _tokens.length; i++) {
            address token = _tokens[i];
            prices[token] = _prices[i];
            if (fastPriceEvents != address(0)) {
              IFastPriceEvents(fastPriceEvents).emitPriceEvent(token, _prices[i]);
            }
        }
        lastUpdatedAt = block.timestamp;
    }

    function setCompactedPrices(uint256[] memory _priceBitArray) external onlyAdmin {
        lastUpdatedAt = block.timestamp;

        for (uint256 i = 0; i < _priceBitArray.length; i++) {
            uint256 priceBits = _priceBitArray[i];

            for (uint256 j = 0; j < 8; j++) {
                uint256 index = i * 8 + j;
                if (index >= tokens.length) { return; }

                uint256 startBit = 32 * j;
                uint256 price = (priceBits >> startBit) & PRICE_BITMASK;

                address token = tokens[i * 8 + j];
                uint256 tokenPrecision = tokenPrecisions[i * 8 + j];
                uint256 adjustedPrice = price.mul(PRICE_PRECISION).div(tokenPrecision);
                prices[token] = adjustedPrice;

                if (fastPriceEvents != address(0)) {
                  IFastPriceEvents(fastPriceEvents).emitPriceEvent(token, adjustedPrice);
                }
            }
        }
    }

    function disableFastPrice() external onlySigner {
        require(!disableFastPriceVotes[msg.sender], "FastPriceFeed: already voted");
        disableFastPriceVotes[msg.sender] = true;
        disableFastPriceVoteCount = disableFastPriceVoteCount.add(1);
    }

    function enableFastPrice() external onlySigner {
        require(disableFastPriceVotes[msg.sender], "FastPriceFeed: already enabled");
        disableFastPriceVotes[msg.sender] = false;
        disableFastPriceVoteCount = disableFastPriceVoteCount.sub(1);
    }

    function favorFastPrice() public view returns (bool) {
        return (disableFastPriceVoteCount < minAuthorizations) && !isSpreadEnabled;
    }

    function getPrice(address _token, uint256 _refPrice, bool _maximise) external override view returns (uint256) {
        if (block.timestamp > lastUpdatedAt.add(priceDuration)) { return _refPrice; }

        uint256 fastPrice = prices[_token];
        if (fastPrice == 0) { return _refPrice; }

        uint256 maxPrice = _refPrice.mul(BASIS_POINTS_DIVISOR.add(maxDeviationBasisPoints)).div(BASIS_POINTS_DIVISOR);
        uint256 minPrice = _refPrice.mul(BASIS_POINTS_DIVISOR.sub(maxDeviationBasisPoints)).div(BASIS_POINTS_DIVISOR);

        if (favorFastPrice()) {
            if (fastPrice >= minPrice && fastPrice <= maxPrice) {
                if (_maximise) {
                    if (_refPrice > fastPrice) {
                        uint256 volPrice = fastPrice.mul(BASIS_POINTS_DIVISOR.add(volBasisPoints)).div(BASIS_POINTS_DIVISOR);
                        // the volPrice should not be more than _refPrice
                        return volPrice > _refPrice ? _refPrice : volPrice;
                    }
                    return fastPrice;
                }

                if (_refPrice < fastPrice) {
                    uint256 volPrice = fastPrice.mul(BASIS_POINTS_DIVISOR.sub(volBasisPoints)).div(BASIS_POINTS_DIVISOR);
                    // the volPrice should not be less than _refPrice
                    return volPrice < _refPrice ? _refPrice : volPrice;
                }

                return fastPrice;
            }
        }

        if (_maximise) {
            if (_refPrice > fastPrice) { return _refPrice; }
            return fastPrice > maxPrice ? maxPrice : fastPrice;
        }

        if (_refPrice < fastPrice) { return _refPrice; }
        return fastPrice < minPrice ? minPrice : fastPrice;
    }
}

