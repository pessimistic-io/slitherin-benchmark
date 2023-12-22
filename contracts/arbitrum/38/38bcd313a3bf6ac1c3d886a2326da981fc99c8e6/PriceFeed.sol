// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./IUpshotConsumer.sol";

contract PriceFeed is Initializable, OwnableUpgradeable {
    enum PriceMode {
        Oracle,
        Manual
    }

    struct OracleSnapshot {
        bytes32 requestId;
        uint256 timestamp;
    }

    struct ManualSnapshot {
        uint256 price;
        uint256 timestamp;
    }

    PriceMode public priceMode;
    IUpshotConsumer public upshotConsumer;
    address public manualBot;
    address public oracleBot;
    mapping(bytes32 => uint256) public keyToAssetIdMap; // price feed key => asset id
    mapping(bytes32 => OracleSnapshot[]) public oracleSnapshots;
    mapping(bytes32 => ManualSnapshot[]) public manualSnapshots;

    event OracleSnapshotted(bytes32 indexed key, bytes32 indexed requestId, address bot);
    event ManualSnapshotted(bytes32 indexed key, uint256 price, address bot);

    modifier onlyManualBot() {
        require(_msgSender() == manualBot, "PriceFeed: caller != manualBot");
        _;
    }

    modifier onlyOracleBot() {
        require(_msgSender() == oracleBot, "PriceFeed: caller != oracleBot");
        _;
    }

    function initialize(IUpshotConsumer _upshotConsumer) public initializer {
        __Ownable_init();
        upshotConsumer = _upshotConsumer;
    }

    function addPriceFeedKey(bytes32 _key, uint256 _assetId) public onlyOwner {
        keyToAssetIdMap[_key] = _assetId;
    }

    function updatePriceOracle(bytes32 _key) public onlyOracleBot {
        require(priceFeedKeyExists(_key), "PriceFeed: invalid key");
        bytes32 requestId = upshotConsumer.requestPrice(keyToAssetIdMap[_key]);
        OracleSnapshot memory snapshot = OracleSnapshot(requestId, block.timestamp);
        oracleSnapshots[_key].push(snapshot);
        emit OracleSnapshotted(_key, requestId, _msgSender());
    }

    function updateManualPrice(bytes32 _key, uint256 _price) public onlyManualBot {
        require(priceFeedKeyExists(_key), "PriceFeed: invalid key");
        require(_price != 0, "PriceFeed: price cannot be 0");
        ManualSnapshot memory snapshot = ManualSnapshot(_price, block.timestamp);
        manualSnapshots[_key].push(snapshot);
        emit ManualSnapshotted(_key, _price, _msgSender());
    }

    function getPrice(bytes32 _key) public view returns (uint256) {
        require(priceFeedKeyExists(_key), "PriceFeed: invalid key");
        if (priceMode == PriceMode.Oracle) {
            return _getPriceOracle(_key);
        }
        return _getPriceManual(_key);
    }

    function getTwapPrice(bytes32 _key, uint256 _interval) public view returns (uint256) {
        require(priceFeedKeyExists(_key), "PriceFeed: invalid key");
        if (priceMode == PriceMode.Oracle) {
            return _getTwapOracle(_key, _interval);
        }
        return _getTwapManual(_key, _interval);
    }

    function _getPriceOracle(bytes32 _key) internal view returns (uint256 price) {
        (, price, ) = _getLatestFulFilledSnapshot(_key);
    }

    function _getTwapOracle(bytes32 _key, uint256 interval) internal view returns (uint256) {
        uint256 baseTimestamp = block.timestamp - interval;
        (
            OracleSnapshot memory latestSnapshot,
            uint256 price,
            uint256 index
        ) = _getLatestFulFilledSnapshot(_key);
        uint256 latestTimestamp = latestSnapshot.timestamp;
        if (baseTimestamp >= latestTimestamp) {
            return price;
        }
        uint256 currentTimestamp = latestTimestamp;
        uint256 cumulativeTime = block.timestamp - currentTimestamp;
        uint256 weightedPrice = price * cumulativeTime;
        while (currentTimestamp > baseTimestamp && index > 0) {
            unchecked {
                index--;
            }
            OracleSnapshot memory currentSnapshot = oracleSnapshots[_key][index];
            price = upshotConsumer.requestIdResult(currentSnapshot.requestId);
            assert(price != 0);
            if (currentSnapshot.timestamp <= baseTimestamp) {
                weightedPrice += (price * (currentTimestamp - baseTimestamp));
                break;
            }
            cumulativeTime = currentTimestamp - currentSnapshot.timestamp;
            weightedPrice += (price * cumulativeTime);
            currentTimestamp = currentSnapshot.timestamp;
        }
        return weightedPrice / interval;
    }

    function _getTwapManual(bytes32 _key, uint256 interval) internal view returns (uint256) {
        uint256 baseTimestamp = block.timestamp - interval;
        uint256 len = manualSnapshots[_key].length;
        require(len != 0, "PriceFeed: no manual snapshots for key");
        uint256 index = len - 1;
        ManualSnapshot memory latestSnapshot = manualSnapshots[_key][index];
        uint256 latestTimestamp = latestSnapshot.timestamp;
        uint256 latestPrice = latestSnapshot.price;
        uint256 cumulativeTime = block.timestamp - latestTimestamp;
        uint256 weighted = latestPrice * cumulativeTime;
        uint256 currentTimestamp = latestTimestamp;
        while (currentTimestamp > baseTimestamp && index > 0) {
            unchecked {
                index--;
            }
            ManualSnapshot memory currentSnapshot = manualSnapshots[_key][index];
            if (currentSnapshot.timestamp <= baseTimestamp) {
                weighted += (currentSnapshot.price * (currentTimestamp - baseTimestamp));
                break;
            }
            cumulativeTime = currentTimestamp - currentSnapshot.timestamp;
            weighted += (currentSnapshot.price * cumulativeTime);
        }
        return weighted / interval;
    }

    function _getLatestFulFilledSnapshot(bytes32 _key)
        internal
        view
        returns (
            OracleSnapshot memory latestFulFilledSnapshot,
            uint256 latestPrice,
            uint256 index
        )
    {
        uint256 len = oracleSnapshots[_key].length;
        require(len != 0, "PriceFeed: no oracle snapshots for key");
        for (uint256 i = len - 1; i >= 0; ) {
            OracleSnapshot memory snapshot = oracleSnapshots[_key][i];
            uint256 _price = upshotConsumer.requestIdResult(snapshot.requestId);
            if (_price != 0) {
                latestFulFilledSnapshot = snapshot;
                latestPrice = _price;
                index = i;
                break;
            }
            unchecked {
                i--;
            }
        }
        require(latestPrice != 0, "PriceFeed: no fulfilled snapshot found");
    }

    function _getPriceManual(bytes32 _key) internal view returns (uint256) {
        uint256 len = manualSnapshots[_key].length;
        require(len != 0, "PriceFeed: no manual snapshots for key");
        ManualSnapshot memory snapshot = manualSnapshots[_key][len - 1];
        return snapshot.price;
    }

    function setUpshotConsumer(IUpshotConsumer _upshotConsumer) public onlyOwner {
        upshotConsumer = _upshotConsumer;
    }

    function priceFeedKeyExists(bytes32 _key) public view returns (bool) {
        return keyToAssetIdMap[_key] != 0;
    }

    function setOracleBot(address _oracleBot) public onlyOwner {
        oracleBot = _oracleBot;
    }

    function setManualBot(address _manualBot) public onlyOwner {
        manualBot = _manualBot;
    }
}

