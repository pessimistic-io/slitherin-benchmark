// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./EnumerableSet.sol";
import "./IDegenMain.sol";
import "./DegenStructs.sol";
import "./DegenBase.sol";

/**
 * @title DegenMain
 * @author balding-ghost
 * @notice Main contract for the Degen game. It is the core contract that handles all the open orders, active/open positions and closed positions. It is the contract all other contracts interact with. The contract is designed to be called (and itself calls) only trusted contracts. Users can call the contract directly, but none of the functions writing to storage or state are available for non trusted entities. It is the idea that users call the contract via the router contract or the reader contract.
 */
contract DegenMain is IDegenMain, DegenBase {
  using EnumerableSet for EnumerableSet.Bytes32Set;
  using EnumerableSet for EnumerableSet.UintSet;

  // incrementing order index
  uint256 internal orderCount;

  /**
   * DegenMain contract - storage layout
   *
   * Data storage of the DegenMain contract
   * EnumerableSet mappings contain the keys or indexes of trades in that particular state
   * openOrdersIndexes_: indexes of all open orders (not yet executed trades)
   * openPositionsKeys_: keys of all open positions (executed trades, in the market)
   * closedPositionsKeys_: keys of all closed positions (executed trades, not in the market)
   * NOTE: A trade can only be in 1 of the 3 states at a time
   *
   * Regular mappings contain the data of a trade
   * orders(orderIndex): data of all open orders
   * positions(positionKey): data of all open positions
   * closedPositions(positionKey): data of all closed positions
   * A single trade will have data in all 3 mappings at some point in time, if a trade goes to a different state the data in these mappings is not deleted. This is done to keep a history of all trades.
   *
   * Main LifeCycle of a user positon (open, exeute, close/liquidate)
   * -> user submits a trade configuration, this data is stored in the OrderInfo struct.
   * -> as the trade is not yet executed in the market it is an 'openOrder' and it is stored in the openOrdersIndexes_ mapping
   * -> if a user executes the order, the order is removed from the openOrdersIndexes_ mapping and the position is added to the openPositionsKeys_ mapping
   * -> the position is now an 'openPosition' and the positionKey is stored in the openPositionsKeys_ mapping
   * -> the data of the position is stored in the PositionInfo struct
   * -> if a user closes the position, the position is removed from the openPositionsKeys_ mapping and added to the closedPositionsKeys_ mapping
   * -> the position is now a 'closedPosition' and the positionKey is stored in the closedPositionsKeys_ mapping
   * -> the data of the position is stored in the ClosedPositionInfo struct
   * -> end of the cycle for this scenario
   *
   * Alternative LifeCycle of a user position (open, cancel)
   * -> user submits a trade configuration, this data is stored in the OrderInfo struct.
   * -> as the trade is not yet executed in the market it is an 'openOrder' and it is stored in the openOrdersIndexes_ mapping
   * -> if a user cancels the order, the order is removed from the openOrdersIndexes_ mapping
   */

  // array/mapping with indexes of all open orders
  EnumerableSet.UintSet internal openOrdersIndexes_;

  // array/mapping with keys of all open positions
  EnumerableSet.Bytes32Set internal openPositionsKeys_;

  // array/mapping with keys of all closed positions
  EnumerableSet.Bytes32Set internal closedPositionsKeys_;

  // positionKey => PositionInfo
  mapping(bytes32 => PositionInfo) public positions;

  // positionKey => ClosedPositionInfo
  mapping(bytes32 => ClosedPositionInfo) public closedPositions;

  // orderIndex => OrderInfo
  mapping(uint256 => OrderInfo) public orders;

  constructor(
    address _targetToken,
    uint256 _decimals,
    address _poolManager,
    bytes32 _pythAssetId,
    address _stableAddress,
    uint256 _stableDecimals
  )
    DegenBase(_targetToken, _decimals, _poolManager, _pythAssetId, _stableAddress, _stableDecimals)
  {}

  /**
   * @notice external function that submits an order by a user
   * @dev a order submission alone will not execute the order, it will only make them executable by the user or a keeper.
   * @param _order order info submitted by the user
   * @return _orderIndex_ index of the order that is submitted
   */
  function submitOrder(OrderInfo memory _order) external onlyRouter returns (uint256 _orderIndex_) {
    _orderIndex_ = _submitOrder(_order);
  }

  /**
   * @notice external function that cancels an order
   * @dev advised that this function is called via the router
   * @dev an order can only be cancelled if it is not active or not already cancelled
   * @param _orderIndex_ index of the active order
   * @param _caller address that is requesting the cancel (only the owner can cancel)
   * @return wagerReturned_ amount of margin that is returned to the user
   */
  function cancelOrder(
    uint256 _orderIndex_,
    address _caller
  ) external onlyRouter returns (uint256 wagerReturned_) {
    wagerReturned_ = _cancelOrder(_orderIndex_, _caller);
  }

  function cancelOrderPoolManager(
    uint256 _orderIndex_,
    address _caller
  ) external onlyPoolManagerController returns (uint256 wagerReturned_) {
    wagerReturned_ = _cancelOrder(_orderIndex_, _caller);
  }

  /**
   * @notice internal function that executes an order
   * @dev advised that this function is called via the router
   * @dev an order can only be executed if it is active and not already opened
   * @param _orderIndex_ index of the order
   * @param _assetPrice price of the asset at the time of execution
   * @param _marginAmountUsdc position size of the open position in usdc
   * @return positionKey_ key of the position that was opened
   */
  function executeOrder(
    uint256 _orderIndex_,
    uint256 _assetPrice,
    uint256 _marginAmountUsdc
  ) external onlyRouter returns (bytes32 positionKey_) {
    positionKey_ = _executeOrder(_orderIndex_, _assetPrice, _marginAmountUsdc);
  }

  /**
   * @notice internal function that liquidates a position
   * @dev advised that this function is called via the router
   * @dev a position can only be liquidated if it is active and not already closed
   * @param _positionKey key of the position
   * @param _caller address that is requesting the liquidation (only the owner can liquidate)
   * @param _assetPrice price of the asset at the time of liquidation
   */
  function liquidatePosition(
    bytes32 _positionKey,
    address _caller,
    uint256 _assetPrice
  ) external onlyRouter {
    require(openPositionsKeys_.contains(_positionKey), "Degen: position not found");
    PositionInfo memory position_ = positions[_positionKey];
    require(position_.player != _caller, "Degen: cannot liquidate own position");
    require(position_.isOpen, "Degen: position already closed");

    (
      int256 INT_pnlUsd_,
      bool isPositionValueNegative_,
      uint256 interestAccruedUsd_
    ) = _calculatePnlAndInterestUsd(
        position_.marginAmountUsd,
        position_.positionSizeUsd,
        position_.priceOpened,
        _assetPrice,
        position_.fundingRateOpen,
        position_.timestampOpened,
        block.timestamp,
        fundingRateTimeBuffer,
        position_.isLong
      );

    bool isRegularLiquidation = (INT_pnlUsd_ < 0) &&
      uint256(-1 * INT_pnlUsd_) >= _calculateEffectiveMargin(position_.marginAmountUsd);

    if (isRegularLiquidation || isPositionValueNegative_) {
      // position is liquidatable the negative pnl is larger or equal to the effective margin
      require(!closedPositionsKeys_.contains(_positionKey), "Degen: position already closed");
      ClosedPositionInfo memory closedPosition_ = poolManager.processLiquidationClose(
        _positionKey,
        position_.player,
        _caller, // is the liquidator
        position_.marginAmountUsd,
        interestAccruedUsd_,
        _assetPrice,
        INT_pnlUsd_,
        isPositionValueNegative_,
        position_.marginAsset
      );
      _decreaseOpenInterest(position_.isLong, position_.positionSizeInTargetAsset);
      positions[_positionKey].isOpen = false;
      closedPositions[_positionKey] = closedPosition_;
      openPositionsKeys_.remove(_positionKey);
      closedPositionsKeys_.add(_positionKey);

      // 3rd field is true if the position was liquidated by funding interest
      emit PositionLiquidated(_positionKey, closedPosition_, isPositionValueNegative_);
    } else {
      revert("Degen: position not liquidatable - threshold not reached");
    }
  }

  /**
   * @notice internal function that closes a position
   * @dev advised that this function is called via the router
   * @dev a position can only be closed if the position is open
   * @param _positionKey key of the position
   * @param _caller address that is requesting the close (only the owner can close)
   * @param _assetPrice price of the asset at the time of closing
   */
  function closePosition(
    bytes32 _positionKey,
    address _caller,
    uint256 _assetPrice
  ) external onlyRouter {
    require(openPositionsKeys_.contains(_positionKey), "Degen: position not found");
    PositionInfo memory position_ = positions[_positionKey];
    require(position_.player == _caller, "Degen: not position owner");
    require(position_.isOpen, "Degen: position already closed");
    position_.isOpen = false;

    // manual close is only allowed if the position has been open for the minimum time configured
    if (!_isUserPositionCloseAllowed(position_.timestampOpened)) {
      revert("Degen: position close not allowed too early");
    }

    require(!closedPositionsKeys_.contains(_positionKey), "Degen: position already closed");

    (
      int256 INT_pnlUsd_,
      bool _isPositionValueNegative,
      uint256 interestAccruedUsd_
    ) = _calculatePnlAndInterestUsd(
        position_.marginAmountUsd,
        position_.positionSizeUsd,
        position_.priceOpened,
        _assetPrice,
        position_.fundingRateOpen,
        position_.timestampOpened,
        block.timestamp,
        fundingRateTimeBuffer,
        position_.isLong
      );

    _decreaseOpenInterest(position_.isLong, position_.positionSizeInTargetAsset);

    (
      ClosedPositionInfo memory closedPosition_,
      uint256 marginAssetAmount_,
      uint256 feesPaid_
    ) = poolManager.closePosition(
        _positionKey,
        position_,
        _caller,
        _assetPrice,
        interestAccruedUsd_,
        INT_pnlUsd_,
        _isPositionValueNegative
      );

    closedPositions[_positionKey] = closedPosition_;
    positions[_positionKey] = position_;
    openPositionsKeys_.remove(_positionKey);
    closedPositionsKeys_.add(_positionKey);

    emit PositionClosed(_positionKey, closedPosition_, marginAssetAmount_, feesPaid_);
  }

  // View Functions

  /**
   * @notice view function that calculates the amount of funding rate interest that has accrued
   * @dev advised that this function is called via the router
   * @param _positionKey key of the position to check funding interest amount for
   * @param _timestampAt timestamp to check funding interest amount for
   */
  function calculateInterestPosition(
    bytes32 _positionKey,
    uint256 _timestampAt
  ) public view returns (uint256 interestAccruedUsd_) {
    PositionInfo memory position_ = positions[_positionKey];
    interestAccruedUsd_ = _calculateAmountOfFundingRateInterestUsd(
      position_.timestampOpened,
      _timestampAt,
      position_.fundingRateOpen,
      position_.positionSizeUsd,
      fundingRateTimeBuffer
    );
  }

  /**
   * @notice view function taht returns the P/L of a position (including interest)
   * @dev advised that this function is called via the router
   * @param _positionKey key of the position
   * @param _assetPrice asset price to calculate the P/L against
   * @param _timestampAt timestamp to calculate the P/L against
   * @return INT_pnlUsd_ P/L of the position in the asset, this is always a positive number, if pnl is negative isPnlPositive_ will be false
   */
  function netPnlOfPosition(
    bytes32 _positionKey,
    uint256 _assetPrice,
    uint256 _timestampAt
  ) external view returns (int256 INT_pnlUsd_) {
    // check if position exists
    require(openPositionsKeys_.contains(_positionKey), "Degen: position not found");
    PositionInfo memory position_ = positions[_positionKey];
    // calculate pnl
    (INT_pnlUsd_, , ) = _calculatePnlAndInterestUsd(
      position_.marginAmountUsd,
      position_.positionSizeUsd,
      position_.priceOpened,
      _assetPrice,
      position_.fundingRateOpen,
      position_.timestampOpened,
      _timestampAt,
      fundingRateTimeBuffer,
      position_.isLong
    );
  }

  /**
   * @notice view function that returns if a position is liquidatable at a certain time and asset price
   * @dev advised that this function is called via the router
   * @param _positionKey key of the position to check if liquidatable
   * @param _assetPrice asset price to check if liquidatable at
   * @param _timestampAt timestamp to check if liquidatable at
   */
  function isPositionLiquidatableByKeyAtTime(
    bytes32 _positionKey,
    uint256 _assetPrice,
    uint256 _timestampAt
  ) external view returns (bool isPositionLiquidatable_) {
    // check if position exists
    require(openPositionsKeys_.contains(_positionKey), "Degen: position not found");
    isPositionLiquidatable_ = _isPositionLiquidatableByKey(_positionKey, _assetPrice, _timestampAt);
  }

  /**
   * @notice view function that returns the info of an open order
   * @dev note that an order is a non-market executed trade configuration
   * @param _orderIndex index of the order
   */
  function returnOrderInfo(
    uint256 _orderIndex
  ) external view returns (OrderInfo memory orderInfo_) {
    orderInfo_ = orders[_orderIndex];
    require(orderInfo_.player != address(0), "Degen: order not found");
    return orderInfo_;
  }

  /**
   * @notice view function that returns the info of an open position
   * @dev note that a position is a market executed trade
   * @param _positionKey key of the position
   */
  function returnOpenPositionInfo(
    bytes32 _positionKey
  ) external view returns (PositionInfo memory positionInfo_) {
    require(openPositionsKeys_.contains(_positionKey), "Degen: position not found");
    positionInfo_ = positions[_positionKey];
  }

  /**
   * @notice view function that returns the info of a closed position
   * @dev note that a closed position is a market executed trade that was closed (either by user or liquidated)
   * @param _positionKey key of the position
   */
  function returnClosedPositionInfo(
    bytes32 _positionKey
  ) external view returns (ClosedPositionInfo memory closedPositionInfo_) {
    require(closedPositionsKeys_.contains(_positionKey), "Degen: position not found");
    closedPositionInfo_ = closedPositions[_positionKey];
  }

  /**
   * @notice view function that returns the amount of open orders (unexecuted configured trades)
   */
  function amountOpenOrders() external view returns (uint256 openOrdersCount_) {
    openOrdersCount_ = openOrdersIndexes_.length();
  }

  /**
   * @notice view function that returns the amount of open positions (executed trades)
   */
  function amountOpenPositions() external view returns (uint256 openPositionsCount_) {
    openPositionsCount_ = openPositionsKeys_.length();
  }

  /**
   * @notice view function that returns if a position is open
   * @param _positionKey key of the position
   */
  function isOpenPosition(bytes32 _positionKey) external view returns (bool isPositionOpen_) {
    isPositionOpen_ = openPositionsKeys_.contains(_positionKey);
  }

  /**
   * @notice view function that returns if an order is open
   * @param _orderIndex index of the order
   */
  function isOpenOrder(uint256 _orderIndex) external view returns (bool isOpenOrder_) {
    isOpenOrder_ = openOrdersIndexes_.contains(_orderIndex);
  }

  /**
   * @notice function returns if a position is closed
   * @param _positionKey key of the position
   */
  function isClosedPosition(bytes32 _positionKey) external view returns (bool isClosedPosition_) {
    // check if the position was ever open to begin with
    require(positions[_positionKey].player != address(0), "Degen: position never opened");
    isClosedPosition_ = closedPositionsKeys_.contains(_positionKey);
  }

  function getOpenPositionsInfo() external view returns (PositionInfo[] memory _positions) {
    _positions = new PositionInfo[](openPositionsKeys_.length());
    for (uint256 i = 0; i < openPositionsKeys_.length(); i++) {
      _positions[i] = positions[openPositionsKeys_.at(i)];
    }
  }

  function getOpenPositionKeys() external view returns (bytes32[] memory _positionKeys) {
    _positionKeys = new bytes32[](openPositionsKeys_.length());
    for (uint256 i = 0; i < openPositionsKeys_.length(); i++) {
      _positionKeys[i] = openPositionsKeys_.at(i);
    }
  }

  function getAllOpenOrdersInfo() external view returns (OrderInfo[] memory _orders) {
    _orders = new OrderInfo[](openOrdersIndexes_.length());
    for (uint256 i = 0; i < openOrdersIndexes_.length(); i++) {
      _orders[i] = orders[openOrdersIndexes_.at(i)];
    }
  }

  function getAllOpenOrderIndexes() external view returns (uint256[] memory _orderIndexes) {
    _orderIndexes = new uint256[](openOrdersIndexes_.length());
    for (uint256 i = 0; i < openOrdersIndexes_.length(); i++) {
      _orderIndexes[i] = openOrdersIndexes_.at(i);
    }
  }

  // function that returns all the closed positions
  function getAllClosedPositionsInfo()
    external
    view
    returns (ClosedPositionInfo[] memory _positions)
  {
    _positions = new ClosedPositionInfo[](closedPositionsKeys_.length());
    for (uint256 i = 0; i < closedPositionsKeys_.length(); i++) {
      _positions[i] = closedPositions[closedPositionsKeys_.at(i)];
    }
  }

  function getPositionKeyOfOrderIndex(
    uint256 _orderIndex
  ) external view returns (bytes32 positionKey_) {
    OrderInfo memory order_ = orders[_orderIndex];
    require(order_.player != address(0), "Degen: order not found");
    positionKey_ = _getPositionKey(order_.player, order_.isLong, _orderIndex);
  }

  /**
   * @notice function returns all the position keys of positions that are liquidatable
   * @dev it is advised that this function is called by the router
   * @param _assetPrice the price to check liquidatable positions against
   * @param _timestampAt the time to check liquidatable positions against
   */
  function getAllLiquidatablePositions(
    uint256 _assetPrice,
    uint256 _timestampAt
  ) external view returns (bytes32[] memory _liquidatablePositions) {
    bytes32[] memory tempPositions_ = new bytes32[](openPositionsKeys_.length());
    uint256 count_ = 0;
    for (uint256 i = 0; i < openPositionsKeys_.length(); i++) {
      bytes32 positionKey_ = openPositionsKeys_.at(i);
      bool isLiquidatable_ = _isPositionLiquidatableByKey(positionKey_, _assetPrice, _timestampAt);
      if (isLiquidatable_) {
        tempPositions_[count_] = positionKey_;
        count_++;
      }
    }

    // Create a new array with the correct size
    _liquidatablePositions = new bytes32[](count_);
    for (uint256 i = 0; i < count_; i++) {
      _liquidatablePositions[i] = tempPositions_[i];
    }
    return _liquidatablePositions;
  }

  // Internal functions
  function _getPositionKey(
    address _account,
    bool _isLong,
    uint256 _posId
  ) internal view returns (bytes32 positionKey_) {
    unchecked {
      positionKey_ = keccak256(
        abi.encodePacked(_account, address(targetMarketToken), _isLong, _posId)
      );
    }
  }

  /**
   * @notice internal view returns the amount of funding rate accured
   * @param _timeStampOpened timestamp when the position was opened
   * @param _currentTimeStamp current timestamp
   * @param _fundingRate funding rate of the position
   * @param _positionSizeUsd size of the position
   */
  function _calculateAmountOfFundingRateInterestUsd(
    uint256 _timeStampOpened,
    uint256 _currentTimeStamp,
    uint256 _fundingRate,
    uint256 _positionSizeUsd,
    uint256 _fundingRateTimeBuffer
  ) internal view returns (uint256 interestAccruedUsd_) {
    if (_currentTimeStamp >= _timeStampOpened + _fundingRateTimeBuffer) {
      uint256 feeApplicableCount_ = (_currentTimeStamp - _timeStampOpened) / fundingFeePeriod;
      uint256 fundingFeePercent_ = (_fundingRate * feeApplicableCount_) / fundingFeePeriod;
      if (fundingFeePercent_ > BASIS_POINTS) {
        fundingFeePercent_ = BASIS_POINTS;
      }
      interestAccruedUsd_ = (_positionSizeUsd * fundingFeePercent_) / BASIS_POINTS;
    } else {
      interestAccruedUsd_ = 0;
    }
  }

  function _isPositionLiquidatableByKey(
    bytes32 _positionKey,
    uint256 _assetPrice,
    uint256 _timestampAt
  ) internal view returns (bool isPositionLiquidatable_) {
    PositionInfo memory position_ = positions[_positionKey];
    isPositionLiquidatable_ = _isPositionLiquidable(
      position_.marginAmountUsd,
      position_.positionSizeUsd,
      position_.priceOpened,
      _assetPrice,
      position_.fundingRateOpen,
      position_.timestampOpened,
      _timestampAt,
      fundingRateTimeBuffer,
      position_.isLong
    );
  }

  /**
   * @notice internal view returns true if the position is liquidatable, false if it is not
   * @param _marginAmount margin amount when the position was opened in usd, scaled 1e18
   * @param _positionSizeUsd size of the position scaled 1e18
   * @param _positionPriceOnOpen price when the position was opened scaled 1e18
   * @param _priceCurrently current price scaled 1e18
   * @param _fundingRate funding rate of the position
   * @param _timeOpened timestamp when the position was opened
   * @param _timeCurrently current timestamp
   * @param _fundingRateTimeBuffer time buffer for the funding rate
   * @param _isLong true if the user is betting on the price going up, if false the user is betting on the price going down
   * @return isLiquidatble_ true if the position is liquidatable, false if it is not
   */
  function _isPositionLiquidable(
    uint256 _marginAmount,
    uint256 _positionSizeUsd,
    uint256 _positionPriceOnOpen,
    uint256 _priceCurrently,
    uint256 _fundingRate,
    uint256 _timeOpened,
    uint256 _timeCurrently,
    uint256 _fundingRateTimeBuffer,
    bool _isLong
  ) internal view returns (bool isLiquidatble_) {
    (int256 INT_pnlUsd_, bool _isPositionValueNegative, ) = _calculatePnlAndInterestUsd(
      _marginAmount,
      _positionSizeUsd,
      _positionPriceOnOpen,
      _priceCurrently,
      _fundingRate,
      _timeOpened,
      _timeCurrently,
      _fundingRateTimeBuffer,
      _isLong
    );

    bool isRegularLiquidation_ = (INT_pnlUsd_ < 0) &&
      uint256(-1 * INT_pnlUsd_) >= _calculateEffectiveMargin(_marginAmount);

    if (isRegularLiquidation_) {
      return true;
    }
    if (_isPositionValueNegative) {
      return true;
    }
  }

  function _calculateEffectiveMargin(
    uint256 _marginAmount
  ) internal view returns (uint256 effectiveMargin_) {
    unchecked {
      effectiveMargin_ = (_marginAmount * liquidationThreshold) / BASIS_POINTS;
    }
  }

  /**
   * @notice internal function that calculates the PnL and Interest
   * @param _positionSizeUsd size of the position
   * @param _positionPriceOnOpen price when the position was opened
   * @param _priceCurrently price at which  the P/L is calculated
   * @param _fundingRate funding rate the P/L is calculated with
   * @param _timeOpened timestamp the P/L is calculated from
   * @param _timeCurrently timestamp to use as current time
   * @param _fundingRateTimeBuffer time buffer for the funding rate
   * @param _isLong true if the user is betting on the price going up, if false the user is betting on the price going down
   * @return INT_pnlUsd_ P/L of the position in the asset, this could be a positive or negative number
   * @return _isPositionValueNegative true if the position is liquidated, false if it is not
   * @return interestAccruedUsd_ accrued interest on the position

   */
  function _calculatePnlAndInterestUsd(
    uint256 _marginAmount,
    uint256 _positionSizeUsd,
    uint256 _positionPriceOnOpen,
    uint256 _priceCurrently,
    uint256 _fundingRate,
    uint256 _timeOpened,
    uint256 _timeCurrently,
    uint256 _fundingRateTimeBuffer,
    bool _isLong
  )
    internal
    view
    returns (int256 INT_pnlUsd_, bool _isPositionValueNegative, uint256 interestAccruedUsd_)
  {
    interestAccruedUsd_ = _calculateAmountOfFundingRateInterestUsd(
      _timeOpened,
      _timeCurrently,
      _fundingRate,
      _positionSizeUsd,
      _fundingRateTimeBuffer
    );

    INT_pnlUsd_ = _calculatePnl(_positionSizeUsd, _positionPriceOnOpen, _priceCurrently, _isLong);

    // Calculate result margin amount
    if (int256(_marginAmount) + INT_pnlUsd_ <= int256(interestAccruedUsd_)) {
      // Margin + pnl is smaller than interest, so the margin becomes 0 or negative, so the net position value becomes negative
      _isPositionValueNegative = true;
    }
  }

  /**
   * @notice internal view returns the P/L of a position
   * @param _positionSizeUsd size of the position scaled 1e18
   * @param _positionPriceOnOpen price when the position was opened in usd, scaled 1e18
   * @param _priceCurrently current price scaled 1e18
   * @param _isLong true if the user is betting on the price going up, if false the user is betting on the price going down
   * @return INT_pnlUsd_ P/L of the position in the asset, this could be a positive or negative number, scaled 1e18 so pnl +$90 is 90 * 1e18
   */
  function _calculatePnl(
    uint256 _positionSizeUsd,
    uint256 _positionPriceOnOpen,
    uint256 _priceCurrently,
    bool _isLong // true if the user is betting on the price going up, if false the user is betting on the price going down (short)§
  ) internal pure returns (int256 INT_pnlUsd_) {
    uint256 _amountOfAssets = (_positionSizeUsd * PRICE_PRECISION) / _positionPriceOnOpen;
    int256 priceDiff = int256(_priceCurrently) - int256(_positionPriceOnOpen);
    if (_isLong) {
      INT_pnlUsd_ = (int256(_amountOfAssets) * priceDiff) / int256(PRICE_PRECISION);
    } else {
      INT_pnlUsd_ = (int256(_amountOfAssets) * -1 * priceDiff) / int256(PRICE_PRECISION);
    }
  }

  /**
   * @notice internal function that submits an order
   * @dev a submitted order is not yet active, it needs to be executed
   * @param _order order to be submitted
   * @return _orderIndex_ index of the order that is submitted
   */
  function _submitOrder(OrderInfo memory _order) internal returns (uint256 _orderIndex_) {
    _checkOpenOrderAllowed();
    // check if leverage is within bounds
    require(_order.positionLeverage >= minLeverage, "Degen: leverage too low");
    require(_order.positionLeverage <= maxLeverage, "Degen: leverage too high");

    uint256 orderIndex_ = orderCount;
    _order.timestampCreated = uint32(block.timestamp);
    orders[orderIndex_] = _order;
    openOrdersIndexes_.add(orderIndex_);
    unchecked {
      orderCount++;
    }
    emit OrderSubmitted(orderIndex_, _order);
    return orderIndex_;
  }

  /**
   * @notice internal function that cancels an unopened order
   * @dev canceling is only possible if the order is not active or not already cancelled
   * @param _orderIndex_ index of the active order
   * @param _caller address that is requesting the cancel (only the owner can cancel)
   * @return wagerReturned_ amount of margin that is returned to the user (could be usd or asset)
   */
  function _cancelOrder(
    uint256 _orderIndex_,
    address _caller
  ) internal returns (uint256 wagerReturned_) {
    OrderInfo memory order_ = orders[_orderIndex_];
    require(order_.player == _caller, "Degen: only owner or admin can cancel order");
    require(!order_.isOpened, "Degen: can't cancel active order");
    require(openOrdersIndexes_.contains(_orderIndex_), "Degen: order not found");
    // check if the order is already cancelled
    require(!order_.isCancelled, "Degen: order already cancelled");
    wagerReturned_ = order_.wagerAmount;
    order_.isCancelled = true;
    orders[_orderIndex_] = order_;
    openOrdersIndexes_.remove(_orderIndex_);
    emit OrderCancelled(_orderIndex_, order_);
    return wagerReturned_;
  }

  function _executeOrder(
    uint256 _orderIndex_,
    uint256 _assetPrice,
    uint256 _marginAmountUsdc
  ) internal returns (bytes32 positionKey_) {
    // check if executing orders is enabled
    _checkOpenPositionAllowed();
    // fetch order data
    OrderInfo memory order_ = orders[_orderIndex_];
    poolManager.transferInMarginUsdc(order_.player, _marginAmountUsdc);

    uint256 positionSizeUsd_;
    uint256 marginValueUsd_;

    (positionSizeUsd_, marginValueUsd_) = _checkPositionSizeWagerInUsdc(
      order_.positionLeverage,
      _marginAmountUsdc
    );

    // check order size and if it is not expired
    require(order_.timestampExpired >= block.timestamp, "Degen: position expired");
    // check if the order is open
    require(openOrdersIndexes_.contains(_orderIndex_), "Degen: order not found");
    openOrdersIndexes_.remove(_orderIndex_);
    require(!order_.isOpened, "Degen: position already opened");
    require(_assetPrice >= order_.minOpenPrice, "Degen: price outside of min limits");
    require(_assetPrice <= order_.maxOpenPrice, "Degen: price outside of max limits");

    orders[_orderIndex_].isOpened = true;

    // compute position key
    positionKey_ = _getPositionKey(order_.player, order_.isLong, _orderIndex_);
    require(!openPositionsKeys_.contains(positionKey_), "Degen: position already opened");

    uint256 positionSizeInTargetAsset_ = (positionSizeUsd_ * 10 ** decimalsToken) / _assetPrice;
    openPositionsKeys_.add(positionKey_);

    PositionInfo memory position_;
    position_.isLong = order_.isLong;
    position_.player = order_.player;
    position_.marginAsset = order_.marginAsset;
    position_.orderIndex = uint32(_orderIndex_);
    position_.timestampOpened = uint32(block.timestamp);
    position_.priceOpened = uint96(_assetPrice);
    position_.positionSizeUsd = uint96(positionSizeUsd_);
    position_.marginAmountUsd = uint96(marginValueUsd_);
    _increaseOpenInterest(order_.isLong, positionSizeInTargetAsset_);
    position_.positionSizeInTargetAsset = uint96(positionSizeInTargetAsset_);
    position_.fundingRateOpen = uint32(_updateFundingRate(order_.isLong));
    position_.maxPositionProfitUsd = uint96(_maxPositionProfitUsd());
    position_.isOpen = true;
    positions[positionKey_] = position_;

    emit OrderExecuted(_orderIndex_, positionKey_, position_);
    return positionKey_;
  }
}

