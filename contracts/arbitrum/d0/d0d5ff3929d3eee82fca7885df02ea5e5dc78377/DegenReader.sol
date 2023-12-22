// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IDegenMain.sol";
import "./IDegenPriceManager.sol";
import "./IDegenRouter.sol";
import "./IDegenReader.sol";
import "./IDegenPoolManager.sol";

/**
 * @title DegenReader
 * @author balding-ghost
 * @notice The DegenReader contract should be used for all reading of the degen game state. It provides functions to read out state correctly. It is technically possible to direclty read data from DegenMain however this is not recommended as it is easy to make mistakes.
 */
contract DegenReader is IDegenReader {
  uint256 internal constant PRICE_PRECISION = 1e18;
  uint256 public constant BASIS_POINTS = 1e6;
  IDegenMain public immutable degenMain;
  IDegenRouter public immutable router;
  IDegenPoolManager public immutable poolManager;
  IERC20 public immutable targetToken;
  bytes32 public immutable pythAssetId;
  IDegenPriceManager public immutable priceManager;

  constructor(address _degenMain, address _targetToken) {
    degenMain = IDegenMain(_degenMain);
    router = IDegenRouter(IDegenBase(_degenMain).router());
    priceManager = IDegenPriceManager(router.priceManager());
    poolManager = IDegenPoolManager(router.poolManager());
    pythAssetId = priceManager.pythAssetId();
    targetToken = IERC20(_targetToken);
  }

  function calculateInterestPosition(
    bytes32 _positionKey,
    uint256 _timestampAt
  ) external view returns (uint256 interestAccruedUsd_) {
    interestAccruedUsd_ = degenMain.calculateInterestPosition(_positionKey, _timestampAt);
  }

  function netPnlOfPositionWithInterest(
    bytes32 _positionKey,
    uint256 _assetPrice,
    uint256 _timestampAt
  ) external view returns (int256 pnlUsd_) {
    (pnlUsd_) = _netPnlOfPosition(_positionKey, _assetPrice, _timestampAt);
  }

  function netPnlOfPositionWithInterestUpdateData(
    bytes32 _positionKey,
    bytes memory _updateData,
    uint256 _timestampAt
  ) external view returns (int256 pnlUsd_) {
    uint256 assetPrice_ = _getPriceFromUpdateData(_updateData);
    (pnlUsd_) = _netPnlOfPosition(_positionKey, assetPrice_, _timestampAt);
  }

  function isPositionLiquidatableByKeyAtTimeUpdateData(
    bytes32 _positionKey,
    bytes memory _updateData,
    uint256 _timestampAt
  ) external view returns (bool isPositionLiquidatable_) {
    uint256 assetPrice_ = _getPriceFromUpdateData(_updateData);
    isPositionLiquidatable_ = _isPositionLiquidatable(_positionKey, assetPrice_, _timestampAt);
  }

  function isPositionLiquidatable(
    bytes32 _positionKey
  ) external view returns (bool isPositionLiquidatable_) {
    (uint256 assetPrice_, ) = priceManager.getLastPriceUnsafe();
    isPositionLiquidatable_ = degenMain.isPositionLiquidatableByKeyAtTime(
      _positionKey,
      assetPrice_,
      block.timestamp
    );
  }

  function _isUserPositionCloseAllowed(
    uint256 _positionOpenTimestamp
  ) internal view returns (bool isAllowed_) {
    unchecked {
      isAllowed_ = block.timestamp >= _positionOpenTimestamp + degenMain.minimumPositionDuration();
    }
  }

  function isPositionLiquidatableUpdateData(
    bytes32 _positionKey,
    bytes memory _updateData
  ) external view returns (bool isPositionLiquidatable_) {
    uint256 assetPrice_ = _getPriceFromUpdateData(_updateData);
    isPositionLiquidatable_ = _isPositionLiquidatable(_positionKey, assetPrice_, block.timestamp);
  }

  function isPositionLiquidatableByKeyAtTime(
    bytes32 _positionKey,
    uint256 _assetPrice,
    uint256 _timestampAt
  ) external view returns (bool isPositionLiquidatable_) {
    isPositionLiquidatable_ = _isPositionLiquidatable(_positionKey, _assetPrice, _timestampAt);
  }

  function returnOrderInfo(
    uint256 _orderIndex
  ) external view returns (OrderInfo memory orderInfo_) {
    orderInfo_ = degenMain.returnOrderInfo(_orderIndex);
  }

  function returnOpenPositionInfo(
    bytes32 _positionKey
  ) external view returns (PositionInfo memory positionInfo_) {
    positionInfo_ = degenMain.returnOpenPositionInfo(_positionKey);
  }

  function returnClosedPositionInfo(
    bytes32 _positionKey
  ) external view returns (ClosedPositionInfo memory closedPositionInfo_) {
    closedPositionInfo_ = degenMain.returnClosedPositionInfo(_positionKey);
  }

  function amountOpenOrders() external view returns (uint256 openOrdersCount_) {
    openOrdersCount_ = degenMain.amountOpenOrders();
  }

  function amountOpenPositions() external view returns (uint256 openPositionsCount_) {
    openPositionsCount_ = degenMain.amountOpenPositions();
  }

  function isOpenPosition(bytes32 _positionKey) external view returns (bool isPositionOpen_) {
    isPositionOpen_ = degenMain.isOpenPosition(_positionKey);
  }

  function isOpenOrder(uint256 _orderIndex) external view returns (bool isOpenOrder_) {
    isOpenOrder_ = degenMain.isOpenOrder(_orderIndex);
  }

  function isClosedPosition(bytes32 _positionKey) external view returns (bool isClosedPosition_) {
    isClosedPosition_ = degenMain.isClosedPosition(_positionKey);
  }

  function getFundingRate(bool _long) external view returns (uint256 fundingRate_) {
    fundingRate_ = degenMain.getFundingRate(_long);
  }

  function getOpenPositionsInfo() external view returns (PositionInfo[] memory _positions) {
    _positions = degenMain.getOpenPositionsInfo();
  }

  function getOpenPositionKeys() external view returns (bytes32[] memory _positionKeys) {
    _positionKeys = degenMain.getOpenPositionKeys();
  }

  function getAllOpenOrdersInfo() external view returns (OrderInfo[] memory _orders) {
    _orders = degenMain.getAllOpenOrdersInfo();
  }

  function getAllClosedPositionsInfo()
    external
    view
    returns (ClosedPositionInfo[] memory _positions)
  {
    _positions = degenMain.getAllClosedPositionsInfo();
  }

  function getAllOpenOrderIndexes() external view returns (uint256[] memory _orderIndexes) {
    _orderIndexes = degenMain.getAllOpenOrderIndexes();
  }

  function getAllLiquidatablePositions(
    uint256 _assetPrice,
    uint256 _timestampAt
  ) external view returns (bytes32[] memory _liquidatablePositions) {
    _liquidatablePositions = degenMain.getAllLiquidatablePositions(_assetPrice, _timestampAt);
  }

  function getAmountOfLiquidatablePoisitions(
    uint256 _assetPrice,
    uint256 _timestampAt
  ) external view returns (uint256 amountOfLiquidatablePositions_) {
    bytes32[] memory liquidatablePositions_ = degenMain.getAllLiquidatablePositions(
      _assetPrice,
      _timestampAt
    );
    amountOfLiquidatablePositions_ = liquidatablePositions_.length;
  }

  function getAllLiquidatablePositionsUpdateData(
    bytes memory _updateData,
    uint256 _timestampAt
  ) external view returns (bytes32[] memory _liquidatablePositions) {
    uint256 assetPrice_ = _getPriceFromUpdateData(_updateData);
    _liquidatablePositions = degenMain.getAllLiquidatablePositions(assetPrice_, _timestampAt);
  }

  function getAmountOfLiquidatablePositionsUpdateData(
    bytes memory _updateData,
    uint256 _timestampAt
  ) external view returns (uint256 amountOfLiquidatablePositions_) {
    uint256 assetPrice_ = _getPriceFromUpdateData(_updateData);
    bytes32[] memory liquidatablePositions_ = degenMain.getAllLiquidatablePositions(
      assetPrice_,
      _timestampAt
    );
    amountOfLiquidatablePositions_ = liquidatablePositions_.length;
  }

  function isPriceUpdateRequired() external view returns (bool isUpdateNeeded_) {
    uint256 secondsSinceUpdate_ = priceManager.returnFreshnessOfOnChainPrice();
    isUpdateNeeded_ = !_checkPriceFreshness(secondsSinceUpdate_);
  }

  function willUpdateDataUpdateThePrice(
    bytes calldata _updateData
  ) external view returns (bool willUpdatePrice_) {
    PythStructs.PriceFeed memory updateInfo_ = abi.decode(_updateData, (PythStructs.PriceFeed));
    uint256 priceOracleUpdateTimestamp_ = priceManager.timestampLatestPricePublishPyth();
    willUpdatePrice_ = (updateInfo_.price.publishTime > priceOracleUpdateTimestamp_);
  }

  function isUpdateDataRecentEnoughForExecution(
    bytes calldata _updateData
  ) external view returns (bool isRecentEnough_) {
    PythStructs.PriceFeed memory updateInfo_ = abi.decode(_updateData, (PythStructs.PriceFeed));
    isRecentEnough_ = _checkPriceFreshness(block.timestamp - updateInfo_.price.publishTime);
  }

  function returnAllOpenPositionsOfUser(
    address _user
  ) external view returns (PositionInfo[] memory _userPositions) {
    PositionInfo[] memory allPositions_ = degenMain.getOpenPositionsInfo();
    for (uint256 i = 0; i < allPositions_.length; i++) {
      if (allPositions_[i].player == _user) {
        _userPositions[i] = allPositions_[i];
      }
    }
  }

  function returnAllOpenOrdersOfUser(
    address _user
  ) external view returns (OrderInfo[] memory _userOrders) {
    OrderInfo[] memory allOrders_ = degenMain.getAllOpenOrdersInfo();
    for (uint256 i = 0; i < allOrders_.length; i++) {
      if (allOrders_[i].player == _user) {
        _userOrders[i] = allOrders_[i];
      }
    }
  }

  function returnAllClosedPositionsOfUser(
    address _user
  ) external view returns (ClosedPositionInfo[] memory _userPositions) {
    ClosedPositionInfo[] memory allPositions_ = degenMain.getAllClosedPositionsInfo();
    for (uint256 i = 0; i < allPositions_.length; i++) {
      if (allPositions_[i].player == _user) {
        _userPositions[i] = allPositions_[i];
      }
    }
  }

  // internal functions
  function _getPriceFromUpdateData(
    bytes memory _updateData
  ) internal view returns (uint256 price_) {
    PythStructs.PriceFeed memory updateInfo_ = abi.decode(_updateData, (PythStructs.PriceFeed));
    // check if price is valid
    require(updateInfo_.id == pythAssetId, "DegenReader: invalid price feed id");
    price_ = _convertPriceToUint(updateInfo_.price);
  }

  function _convertPriceToUint(
    PythStructs.Price memory priceInfo_
  ) internal pure returns (uint256 assetPrice_) {
    uint256 price = uint256(uint64(priceInfo_.price));
    if (priceInfo_.expo >= 0) {
      uint256 exponent = uint256(uint32(priceInfo_.expo));
      assetPrice_ = price * PRICE_PRECISION * (10 ** exponent);
    } else {
      uint256 exponent = uint256(uint32(-priceInfo_.expo));
      assetPrice_ = (price * PRICE_PRECISION) / (10 ** exponent);
    }
    return assetPrice_;
  }

  function _netPnlOfPosition(
    bytes32 _positionKey,
    uint256 _assetPrice,
    uint256 _timestampAt
  ) internal view returns (int256 pnlUsd_) {
    (pnlUsd_) = degenMain.netPnlOfPosition(_positionKey, _assetPrice, _timestampAt);
  }

  function _isPositionLiquidatable(
    bytes32 _positionKey,
    uint256 _assetPrice,
    uint256 _timestampAt
  ) internal view returns (bool isPositionLiquidatable_) {
    isPositionLiquidatable_ = degenMain.isPositionLiquidatableByKeyAtTime(
      _positionKey,
      _assetPrice,
      _timestampAt
    );
  }

  function _checkPriceFreshness(uint256 _ageOfPricePublish) internal view returns (bool isFresh_) {
    isFresh_ = _ageOfPricePublish <= router.priceFreshnessThreshold();
  }

  // helper functions

  function getPositionKey(
    address _account,
    bool _isLong,
    uint256 _posId
  ) external view returns (bytes32 positionKey_) {
    positionKey_ = _getPositionKey(_account, _isLong, _posId);
  }

  function _getPositionKey(
    address _account,
    bool _isLong,
    uint256 _posId
  ) internal view returns (bytes32 positionKey_) {
    unchecked {
      positionKey_ = keccak256(abi.encodePacked(_account, address(targetToken), _isLong, _posId));
    }
  }
}

