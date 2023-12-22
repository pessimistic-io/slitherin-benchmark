// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import "./IDegenPriceManager.sol";
import "./AccessControl.sol";

/**
 * @title DegenPriceManager
 * @author balding-ghost
 * @notice The DegenPriceManager contract is used to get the price of the asset and to update the price of the asset. The price of the asset is determined by the on-chain price of the asset on pyth (verified price). Every function handled by the router that involves price contains an updateData object that is processed by the the PriceManager contract.
 */
contract DegenPriceManager is IDegenPriceManager, AccessControl {
  uint256 internal constant PRICE_PRECISION = 1e18;
  uint256 public constant BASIS_POINTS = 1e6;
  bytes32 public constant ADMIN_MAIN = bytes32(keccak256("ADMIN_MAIN"));
  bytes32 public constant OPERATOR = bytes32(keccak256("OPERATOR"));

  // asset informaton immutable
  IPyth public immutable pyth;
  bytes32 public immutable pythAssetId;
  address public immutable tokenAddress;
  uint256 public immutable tokenDecimals;

  address public immutable stableTokenAddress;
  uint256 public immutable stableTokenDecimals;

  // price information dynamic
  uint256 public priceOfAssetUint;
  // timestamp of wormhole verified pyth price update
  uint256 public timestampLatestPricePublishPyth;
  PythStructs.Price public mostRecentPricePyth;

  // timestamp of the last time the price was updated, this is not the same as the publishTime of the price (a big difference) a recent update can be an old price if the on-chain price is not updated. This value should not be used to access price freshness.
  uint256 public mostRecentSyncTimestamp;

  /**
   * DegenPriceManager
   * The pricemanager contract determines the price of the asset based on the on-chain price of the asset on pyth (verified price). Every function handled by the router that involves price contains an updateData object that is processed by the the PriceManager contract. 
   * 
   * The main role of the PriceManager contract is to ensure that the most recent and fresh price is used for a trade. The updateData is a encode pyth PriceFeed struct. This struct is defined in the pyth contracts and is as follows:
    
  PriceFeed represents a current aggregate price from pyth publisher feeds.
    struct PriceFeed {
        // The price ID.
        bytes32 id;
        // Latest available price
        Price price;
        // Latest available exponentially-weighted moving average price
        Price emaPrice;
    }
    struct Price {
        // Price
        int64 price;
        // Confidence interval around the price
        uint64 conf;
        // Price exponent
        int32 expo;
        // Unix timestamp describing when the price was published
        uint publishTime;
    }
   * 
   */

  constructor(
    address _pyth,
    bytes32 _pythAssetId,
    address _tokenAddress,
    address _admin,
    uint256 _tokenDecimals,
    address _stableTokenAddress,
    uint256 _stableTokenDecimals
  ) AccessControl() {
    pyth = IPyth(_pyth);
    tokenAddress = _tokenAddress;
    pythAssetId = _pythAssetId;
    tokenDecimals = _tokenDecimals;
    stableTokenAddress = _stableTokenAddress;
    stableTokenDecimals = _stableTokenDecimals;
    _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    _setupRole(ADMIN_MAIN, _admin);
  }

  // modifiers
  modifier onlyAdmin() {
    require(hasRole(ADMIN_MAIN, msg.sender), "DegenPriceManager: not admin main");
    _;
  }

  // configuration functions

  /**
   * @notice function that is called by the router to get the latest price of the asset and update the price if the price is more recent as the price currently set in this contract
   * @param _priceUpdateData updateData is a encode pyth PriceFeed struct
   * @return assetPrice_ the price of the asset in USD with 18 decimals
   * @return secondsSincePublish_ the number of seconds since the returned price was published
   */
  function getLatestAssetPriceAndUpdate(
    bytes calldata _priceUpdateData
  ) external payable returns (uint256 assetPrice_, uint256 secondsSincePublish_) {
    require(hasRole(OPERATOR, msg.sender), "DegenPriceManager: not operator");
    (assetPrice_, secondsSincePublish_) = _getLatestPrice(_priceUpdateData);
  }

  /**
   * @return priceOfAssetUint_ price of the asset in USD with 18 decimals
   * @return isUpdated_ bool indicating if the price is updated
   */
  function syncPriceWithPyth() external returns (uint256 priceOfAssetUint_, bool isUpdated_) {
    (priceOfAssetUint_, isUpdated_) = _syncPriceWithPyth();
  }

  /**
   * @notice manual price update function that is called by a keeper to update the price
   * @dev technically the idea is that the degen price manager pays the 1 wei fee to pyth
   * @dev this function is called by the router to update the price of the asset without using pyth
   * @param _priceUpdateData updateData is a encode pyth PriceFeed struct
   * @return assetPrice_ the price of the asset in USD with 18 decimals
   * @return secondsSincePublish_ the number of seconds since the returned price was published
   // note this function has critial exploit pottential
   */
  function refreshPrice(
    bytes calldata _priceUpdateData
  ) external payable returns (uint256 assetPrice_, uint256 secondsSincePublish_) {
    // the provided priceUpdateData is more recent as provided priceUpdateData
    bytes[] memory bytesArray = new bytes[](1);
    bytesArray[0] = _priceUpdateData;
    // update pyth with the new price
    PythStructs.Price memory mostRecentPrice_ = _refreshPrice(bytesArray);
    assetPrice_ = _convertPriceToUint(mostRecentPrice_);
    priceOfAssetUint = assetPrice_;
    timestampLatestPricePublishPyth = mostRecentPrice_.publishTime;
    return (assetPrice_, block.timestamp - mostRecentPrice_.publishTime);
  }

  // view functions

  function returnMostRecentPricePyth() external view returns (PythStructs.Price memory) {
    // note warning this is an unscaled price and should not be used for calculations as it isn't scaled to 18 decimals
    return mostRecentPricePyth;
  }

  function returnPriceAndUpdate()
    external
    view
    returns (uint256 assetPrice_, uint256 lastUpdateTimestamp_)
  {
    return (priceOfAssetUint, timestampLatestPricePublishPyth);
  }

  function getLastPriceUnsafe()
    public
    view
    returns (uint256 priceOfAssetUint_, uint256 secondsSincePublish_)
  {
    PythStructs.Price memory priceInfo_ = pyth.getEmaPriceUnsafe(pythAssetId);
    priceOfAssetUint_ = _convertPriceToUint(priceInfo_);
    secondsSincePublish_ = block.timestamp - priceInfo_.publishTime;
  }

  function returnFreshnessOfOnChainPrice() external view returns (uint256 secondsSincePublish_) {
    secondsSincePublish_ = _returnFreshnessOfOnChainPrice();
  }

  function tokenToUsd(
    address _token,
    uint256 _tokenAmount
  ) external view override returns (uint256 usdAmount_) {
    require(_token == tokenAddress, "DegenPriceManager: invalid token");
    (uint256 lastPrice_, ) = getLastPriceUnsafe();
    unchecked {
      usdAmount_ = (_tokenAmount * lastPrice_) / (10 ** tokenDecimals);
    }
  }

  function usdToToken(
    address _token,
    uint256 _usdAmount
  ) external view override returns (uint256 tokenAmount_) {
    require(_token == tokenAddress, "DegenPriceManager: invalid token");
    (uint256 lastPrice_, ) = getLastPriceUnsafe();
    unchecked {
      tokenAmount_ = (_usdAmount * (10 ** tokenDecimals)) / lastPrice_;
    }
  }

  function getCurrentTime() external view returns (uint256) {
    return block.timestamp;
  }

  // internal functions

  function _convertPriceToUint(
    PythStructs.Price memory priceInfo_
  ) internal pure returns (uint256 assetPrice_) {
    // we assume that the price of the asset we are tracking can never be truely 0, so we revert if the price is 0, the likelyhood a 0 price read is an error on the side of the oracle than the price actually being 0 in real life
    require(priceInfo_.price > 0, "DegenPriceManager: invalid price");
    uint256 price = uint256(uint64(priceInfo_.price));
    unchecked {
      if (priceInfo_.expo >= 0) {
        uint256 exponent = uint256(uint32(priceInfo_.expo));
        assetPrice_ = price * PRICE_PRECISION * (10 ** exponent);
      } else {
        uint256 exponent = uint256(uint32(-priceInfo_.expo));
        assetPrice_ = (price * PRICE_PRECISION) / (10 ** exponent);
      }
      return assetPrice_;
    }
  }

  function _refreshPrice(
    bytes[] memory priceUpdateData
  ) internal returns (PythStructs.Price memory priceInfoNew_) {
    uint256 fee_ = pyth.getUpdateFee(priceUpdateData);
    // update the pyth price, note that potentially pyth will not actually be updated
    pyth.updatePriceFeeds{value: fee_}(priceUpdateData);
    // fetch the now most recent price from pyth, this could be the price that we just updated or a price that was on-chain verified on pyth and more recent
    priceInfoNew_ = pyth.getEmaPriceUnsafe(pythAssetId);
    mostRecentPricePyth = priceInfoNew_;
    return priceInfoNew_;
  }

  /**
   * @notice internal function that calls pyth to get the latest price and updates the price in this contract if the price is more recent as the price currently set in this contract
   * @dev this function is possibly not terribly usefull if we will use the updateData to update pyth price already, since in that case we will get the most recent price from pyth already
   * @return priceOfAssetUint_ price of the asset in USD with 18 decimals
   * @return isUpdated_ bool indicating if the price in this contract was updated
   */
  function _syncPriceWithPyth() internal returns (uint256 priceOfAssetUint_, bool isUpdated_) {
    PythStructs.Price memory priceInfo_ = pyth.getEmaPriceUnsafe(pythAssetId);
    if (priceInfo_.publishTime > timestampLatestPricePublishPyth) {
      mostRecentPricePyth = priceInfo_;
      priceOfAssetUint = _convertPriceToUint(priceInfo_);
      timestampLatestPricePublishPyth = priceInfo_.publishTime;
      mostRecentSyncTimestamp = block.timestamp;
      emit OnChainPriceUpdated(priceInfo_);
      return (priceOfAssetUint, true);
    } else {
      emit NoOnChainUpdateRequired(priceInfo_);
      return (priceOfAssetUint, false);
    }
  }

  function _returnFreshnessOfOnChainPrice() internal view returns (uint256 secondsSincePublish_) {
    secondsSincePublish_ = block.timestamp - timestampLatestPricePublishPyth;
  }

  function _getLatestPrice(
    bytes calldata _priceUpdateData
  ) internal returns (uint256 assetPrice_, uint256 secondsSincePublish_) {
    // the provided priceUpdateData is more recent as the price currently set in this contract
    bytes[] memory bytesArray = new bytes[](1);
    bytesArray[0] = _priceUpdateData;
    // update pyth with the new price
    PythStructs.Price memory mostRecentPrice_ = _refreshPrice(bytesArray);
    assetPrice_ = _convertPriceToUint(mostRecentPrice_);
    priceOfAssetUint = assetPrice_;
    // store the timestamp of the last time the price was updated (note this value is not really valueble for price freshness)
    mostRecentSyncTimestamp = block.timestamp;
    // set to the timestamp of the most recent price update (so this is the publish price in pyth)
    timestampLatestPricePublishPyth = mostRecentPrice_.publishTime;
    return (assetPrice_, block.timestamp - mostRecentPrice_.publishTime);
  }

  function addOrRemoveAdminMain(address _admin, bool _add) external onlyAdmin {
    if (_add) {
      grantRole(ADMIN_MAIN, _admin);
    } else {
      revokeRole(ADMIN_MAIN, _admin);
    }
  }

  // function that allows the admin to deposit eth to the contract
  receive() external payable {}

  // function that allows the admin to withdraw eth from the contract
  function withdrawEth(address payable _to, uint256 _amount) external onlyAdmin {
    _to.transfer(_amount);
  }
}

