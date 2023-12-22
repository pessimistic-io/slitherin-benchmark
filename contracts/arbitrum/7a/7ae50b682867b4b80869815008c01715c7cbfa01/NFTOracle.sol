// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

import "./OwnableUpgradeable.sol";
import "./SafeMath.sol";

import "./INFTOracle.sol";
import "./IGNft.sol";

contract NFTOracle is INFTOracle, OwnableUpgradeable {
    using SafeMath for uint256;

    /* ========== CONSTANT VARIABLES ========== */

    uint256 private constant DECIMAL_PRECISION = 10**18;

    /* ========== STATE VARIABLES ========== */
    // key is nft contract address
    mapping(address => NFTPriceFeed) public nftPriceFeed;
    address[] public nftPriceFeedKeys;

    // Maximum deviation allowed between two consecutive oracle prices.
    uint256 public maxPriceDeviation; // 20% 18-digit precision.

    // Maximum allowed deviation between two consecutive oracle prices within a certain time frame
    // 18-bit precision.
    uint256 public maxPriceDeviationWithTime; // 10%
    uint256 public timeIntervalWithPrice; // 30 minutes
    uint256 public minUpdateTime; // 10 minutes

    uint256 public twapInterval;

    address public keeper;

    mapping(address => uint256) public twapPrices;
    mapping(address => bool) public nftPaused;

    /* ========== INITIALIZER ========== */

    function initialize(
        uint256 _maxPriceDeviation,
        uint256 _maxPriceDeviationWithTime,
        uint256 _timeIntervalWithPrice,
        uint256 _minUpdateTime,
        uint256 _twapInterval
    ) external initializer {
        __Ownable_init();

        maxPriceDeviation = _maxPriceDeviation;
        maxPriceDeviationWithTime = _maxPriceDeviationWithTime;
        timeIntervalWithPrice = _timeIntervalWithPrice;
        minUpdateTime = _minUpdateTime;
        twapInterval = _twapInterval;
    }

    /* ========== MODIFIERS ========== */

    modifier onlyKeeper() {
        require(msg.sender == keeper || msg.sender == owner(), "NFTOracle: caller is not the owner or keeper");
        _;
    }

    modifier onlyExistedKey(address _nftContract) {
        require(nftPriceFeed[_nftContract].registered == true, "NFTOracle: key not existed");
        _;
    }

    modifier whenNotPaused(address _nftContract) {
        require(!nftPaused[_nftContract], "NFTOracle: nft price feed paused");
        _;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setKeeper(address _keeper) external onlyOwner {
        require(_keeper != address(0), "NFTOracle: invalid keeper address");
        keeper = _keeper;
        emit KeeperUpdated(_keeper);
    }

    function addAssets(
        address[] calldata _nftContracts
    ) external
    onlyOwner
    {
        for (uint256 i = 0; i < _nftContracts.length; i++) {
            _addAsset(_nftContracts[i]);
        }
    }

    function addAsset(
        address _nftContract
    ) external
    onlyOwner
    {
        _addAsset(_nftContract);
    }

    function removeAsset(
        address _nftContract
    ) external
    onlyOwner
    onlyExistedKey(_nftContract)
    {
        delete nftPriceFeed[_nftContract];

        uint256 length = nftPriceFeedKeys.length;

        for (uint256 i = 0; i < length; i++) {
            if (nftPriceFeedKeys[i] == _nftContract) {
                nftPriceFeedKeys[i] = nftPriceFeedKeys[length - 1];
                nftPriceFeedKeys.pop();
                break;
            }
        }

        emit AssetRemoved(_nftContract);
    }

    function setDataValidityParameters(
        uint256 _maxPriceDeviation,
        uint256 _maxPriceDeviationWithTime,
        uint256 _timeIntervalWithPrice,
        uint256 _minUpdateTime
    ) external onlyOwner {
        maxPriceDeviation = _maxPriceDeviation;
        maxPriceDeviationWithTime = _maxPriceDeviationWithTime;
        timeIntervalWithPrice = _timeIntervalWithPrice;
        minUpdateTime = _minUpdateTime;
    }

    function setPause(address _nftContract, bool isPause) external onlyOwner {
        nftPaused[_nftContract] = isPause;
    }

    function setTwapInterval(uint256 _twapInterval) external onlyOwner {
        twapInterval = _twapInterval;
    }

    function setAssetData(
        address _nftContract,
        uint256 _price
    ) external
    onlyKeeper
    whenNotPaused(_nftContract)
    {
        uint256 _timestamp = block.timestamp;
        _setAssetData(_nftContract, _price, _timestamp);
    }

    function setMultipleAssetData(
        address[] calldata _nftContracts,
        uint256[] calldata _prices
    ) external
    onlyKeeper
    {
        require(_nftContracts.length == _prices.length, "NFTOracle: data length not match");
        uint256 _timestamp = block.timestamp;
        for (uint256 i = 0; i < _nftContracts.length; i++) {
            bool _paused = nftPaused[_nftContracts[i]];
            if (!_paused) {
                _setAssetData(_nftContracts[i], _prices[i], _timestamp);
            }
        }
    }

    /* ========== VIEWS ========== */

    function getUnderlyingPrice(address _gNft) external view override returns (uint256) {
        address _nftContract = IGNft(_gNft).underlying();
        uint256 len = getPriceFeedLength(_nftContract);
        require(len > 0, "NFTOracle: no price data");

        uint256 twapPrice = twapPrices[_nftContract];
        if (twapPrice == 0) {
            return nftPriceFeed[_nftContract].nftPriceData[len - 1].price;
        } else {
            return twapPrice;
        }
    }

    function getAssetPrice(address _nftContract) external view override returns (uint256) {
        uint256 len = getPriceFeedLength(_nftContract);
        require(len > 0, "NFTOracle: no price data");

        uint256 twapPrice = twapPrices[_nftContract];
        if (twapPrice == 0) {
            return nftPriceFeed[_nftContract].nftPriceData[len - 1].price;
        } else {
            return twapPrice;
        }
    }

    function getLatestTimestamp(address _nftContract) public view returns (uint256) {
        uint256 len = getPriceFeedLength(_nftContract);
        if (len == 0) {
            return 0;
        }
        return nftPriceFeed[_nftContract].nftPriceData[len - 1].timestamp;
    }

    function getLatestPrice(address _nftContract) public view returns (uint256) {
        uint256 len = getPriceFeedLength(_nftContract);
        if (len == 0) {
            return 0;
        }
        return nftPriceFeed[_nftContract].nftPriceData[len - 1].price;
    }

    function getPreviousPrice(address _nftContract, uint256 _numOfRoundBack) public view returns (uint256) {
        uint256 len = getPriceFeedLength(_nftContract);
        require(len > 0 && _numOfRoundBack < len, "NFTOracle: Not enough history");
        return nftPriceFeed[_nftContract].nftPriceData[len - _numOfRoundBack - 1].price;
    }

    function getPreviousTimestamp(address _nftContract, uint256 _numOfRoundBack) public view returns (uint256) {
        uint256 len = getPriceFeedLength(_nftContract);
        require(len > 0 && _numOfRoundBack < len, "NFTOracle: Not enough history");
        return nftPriceFeed[_nftContract].nftPriceData[len - _numOfRoundBack - 1].timestamp;
    }

    function getPriceFeedLength(address _nftContract) public view returns (uint256) {
        return nftPriceFeed[_nftContract].nftPriceData.length;
    }

    function getLatestRoundId(address _nftContract) external view override returns (uint256) {
        uint256 len = getPriceFeedLength(_nftContract);
        if (len == 0) {
            return 0;
        }
        return nftPriceFeed[_nftContract].nftPriceData[len - 1].roundId;
    }

    function isExistedKey(address _nftContract) public view returns (bool) {
        return nftPriceFeed[_nftContract].registered;
    }

    function nftPriceFeedKeysLength() public view returns (uint256) {
        return nftPriceFeedKeys.length;
    }

    function calculateTwapPrice(address _nftContract) public view returns (uint256) {
        require(nftPriceFeed[_nftContract].registered == true, "NFTOracle: key not existed");
        require(twapInterval != 0, "NFTOracle: interval can't be 0");

        uint256 len = getPriceFeedLength(_nftContract);
        require(len > 0, "NFTOracle: Not Enough history");
        uint256 round = len - 1;
        NFTPriceData memory priceRecord = nftPriceFeed[_nftContract].nftPriceData[round];

        uint256 latestTimestamp = priceRecord.timestamp;
        uint256 baseTimestamp = block.timestamp - twapInterval;

        // if latest updated timestamp is earlier than target timestamp, return the latest price.
        if (latestTimestamp < baseTimestamp || round == 0) {
            return priceRecord.price;
        }

        // rounds are like snapshots, latestRound means the latest price snapshot. follow chainlink naming
        uint256 cumulativeTime = block.timestamp - latestTimestamp;
        uint256 previousTimestamp = latestTimestamp;
        uint256 weightedPrice = priceRecord.price * cumulativeTime;
        while (true) {
            if (round == 0) {
                // if cumulative time less than requested interval, return current twap price
                return weightedPrice / cumulativeTime;
            }

            round = round - 1;
            // get current round timestamp and price
            priceRecord = nftPriceFeed[_nftContract].nftPriceData[round];
            uint256 currentTimestamp = priceRecord.timestamp;
            uint256 price = priceRecord.price;

            // check if current round timestamp is earlier than target timestamp
            if (currentTimestamp <= baseTimestamp) {
                weightedPrice = weightedPrice + (price * (previousTimestamp - baseTimestamp));
                break;
            }

            uint256 timeFraction = previousTimestamp - currentTimestamp;
            weightedPrice = weightedPrice + price * timeFraction;
            cumulativeTime = cumulativeTime + timeFraction;
            previousTimestamp = currentTimestamp;
        }
        return weightedPrice / twapInterval;
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _addAsset(
        address _nftContract
    ) private {
        require(nftPriceFeed[_nftContract].registered == false, "NFTOracle: key existed");
        nftPriceFeed[_nftContract].registered = true;
        nftPriceFeedKeys.push(_nftContract);
        emit AssetAdded(_nftContract);
    }

    function _setAssetData(
        address _nftContract,
        uint256 _price,
        uint256 _timestamp
    ) private {
        require(nftPriceFeed[_nftContract].registered == true, "NFTOracle: key not existed");
        require(_timestamp > getLatestTimestamp(_nftContract), "NFTOracle: incorrect timestamp");
        require(_price > 0, "NFTOracle: price can not be 0");

        bool dataValidity = _checkValidityOfPrice(_nftContract, _price, _timestamp);
        require(dataValidity, "NFTOracle: invalid price data");

        uint256 len = getPriceFeedLength(_nftContract);
        NFTPriceData memory data = NFTPriceData({
            price: _price,
            timestamp: _timestamp,
            roundId: len
        });
        nftPriceFeed[_nftContract].nftPriceData.push(data);

        uint256 twapPrice = calculateTwapPrice(_nftContract);
        twapPrices[_nftContract] = twapPrice;

        emit SetAssetData(_nftContract, _price, _timestamp, len);
        emit SetAssetTwapPrice(_nftContract, twapPrice, _timestamp);
    }

    function _checkValidityOfPrice(
        address _nftContract,
        uint256 _price,
        uint256 _timestamp
    ) private view returns (bool) {
        uint256 len = getPriceFeedLength(_nftContract);
        if (len > 0) {
            uint256 price = nftPriceFeed[_nftContract].nftPriceData[len - 1].price;
            if (_price == price) {
                return true;
            }
            uint256 timestamp = nftPriceFeed[_nftContract].nftPriceData[len - 1].timestamp;
            uint256 percentDeviation;
            if (_price > price) {
                percentDeviation = ((_price - price).mul(DECIMAL_PRECISION)).div(price) ;
            } else {
                percentDeviation = ((price - _price)).mul(DECIMAL_PRECISION).div(price);
            }
            uint256 timeDeviation = _timestamp - timestamp;
            if (percentDeviation > maxPriceDeviation) {
                return false;
            } else if (timeDeviation < minUpdateTime) {
                return false;
            } else if ((percentDeviation > maxPriceDeviationWithTime) && (timeDeviation < timeIntervalWithPrice)) {
                return false;
            }
        }
        return true;
    }
}

