// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ReentrancyGuard.sol";
import "./IDegenMain.sol";
import "./IDegenRouter.sol";
import "./IDegenPriceManager.sol";
import "./IDegenPoolManager.sol";
import "./DegenStructs.sol";
import "./IVault.sol";
import "./IReader.sol";
import "./ISwap.sol";

/**
 * @title DegenRouter
 * @author balding-ghost
 * @notice The DegenRouter contract is used to route calls to the DegenMain contract. The router contract is used to make sure that the price is fresh enough to be used for execution. If the price is not fresh enough the router will not execute the order/position (and depending on configuration it might fail).
 */
contract DegenRouter is IDegenRouter, ReentrancyGuard {
  uint256 public constant MAX_LIQUIDATIONS = 5;
  IDegenMain public immutable degenMain;
  IDegenPriceManager public immutable priceManager;
  IDegenPoolManager public immutable poolManager;
  IVault public immutable vault;
  IReader public immutable reader;
  bytes32 public immutable pythAssetId;
  IERC20 public immutable targetToken;
  IERC20 public immutable stableToken;
  uint256 public immutable minimumFreshness = 1; // at least 1 second to prevent same block reverts
  address public controller;

  ISwap public swap;

  // if true the router will revert if the price is not fresh enough to be used for execution (so it is not executable)
  bool public failOnFailedExecution;

  // amount of seconds that the price needs to be fresh enough to be used for execution
  uint256 public priceFreshnessThreshold;

  // mapping to store allowed wager assets
  mapping(address => bool) public allowedWagerAssets;

  mapping(uint256 => uint256) public wagerInOpenOrdersUsdc;

  mapping(uint256 => uint256) internal amountWagerForOrder;

  mapping(uint256 => address) internal orderToWagerAsset;

  mapping(address => bool) public allowedKeepers;

  modifier onlyKeeper() {
    require(allowedKeepers[msg.sender], "DegenRouter: INVALID_KEEPER");
    _;
  }

  constructor(
    address _degenMain,
    address _priceManager,
    address _poolManager,
    address _controller,
    address _vault,
    address _reader,
    address _swap
  ) {
    degenMain = IDegenMain(_degenMain);
    priceManager = IDegenPriceManager(_priceManager);
    poolManager = IDegenPoolManager(_poolManager);
    targetToken = IERC20(priceManager.tokenAddress());
    stableToken = IERC20(priceManager.stableTokenAddress());
    pythAssetId = priceManager.pythAssetId();
    controller = _controller;
    vault = IVault(_vault);
    reader = IReader(_reader);
    swap = ISwap(_swap);
  }

  /**
   * @notice submits an order to the degenMain contract, so that it becomes available for execution
   * @dev note that the order is not executed by this function
   * @dev note that if the price is not fresh or executable, this function will not fail
   * @param _positionLeverage leverage of the position (multiplier), not scaled at all so 500x leverage is 500
   * @param _wagerAmount amount of margin/wager to use for the position, this is in the asset of the contract or in usdc
   * @param _minOpenPrice minimum price to open the position, note if set to 0 it means that there is no minimum price
   * @param _maxOpenPrice maximum price to open the position, note if set to 0 it means that there is no maximum price
   * @param _timestampExpired timestamp when the order expires
   * @param _isLong bool true if the user is betting on the price going up, if false the user is betting on the price going down
   * @return orderIndex_ uint256 index of the order in the degenMain contract
   */
  function submitOrderManual(
    uint16 _positionLeverage,
    uint96 _wagerAmount,
    uint96 _minOpenPrice,
    uint96 _maxOpenPrice,
    uint32 _timestampExpired,
    address _marginAsset,
    bool _isLong
  ) external nonReentrant returns (uint256 orderIndex_) {
    orderIndex_ = _submitOrder(
      _positionLeverage,
      _wagerAmount,
      _minOpenPrice,
      _maxOpenPrice,
      _timestampExpired,
      _marginAsset,
      _isLong
    );
  }

  function liquidateLiquidatablePositions(
    bytes calldata _updateData
  ) external nonReentrant returns (uint256 amountOfLiquidations_) {
    (uint256 executionPrice_, bool isExecutable_) = _getExecutionPriceAndExecutableCheck(
      _updateData
    );

    bytes32[] memory _liquidatablePositions = degenMain.getAllLiquidatablePositions(
      executionPrice_,
      block.timestamp
    );
    uint256 count_;
    for (uint256 i = 0; i < _liquidatablePositions.length; i++) {
      bytes32 _positionKey = _liquidatablePositions[i];
      _liquidatePosition(_positionKey, executionPrice_, isExecutable_);
      count_++;
      if (count_ >= MAX_LIQUIDATIONS) {
        return count_;
      }
    }
    return count_;
  }

  function liquidateLiquidatablePositionsOnChainPrice()
    external
    nonReentrant
    returns (uint256 amountOfLiquidations_)
  {
    (uint256 assetPrice_, uint256 lastUpdateTimestamp_) = priceManager.returnPriceAndUpdate();

    require(
      _checkPriceFreshness(block.timestamp - lastUpdateTimestamp_),
      "DegenRouter: price update too old update first"
    );

    bytes32[] memory _liquidatablePositions = degenMain.getAllLiquidatablePositions(
      assetPrice_,
      block.timestamp
    );

    uint256 count_;

    for (uint256 i = 0; i < _liquidatablePositions.length; i++) {
      bytes32 _positionKey = _liquidatablePositions[i];
      degenMain.liquidatePosition(_positionKey, msg.sender, assetPrice_);
      emit PositionLiquidated(_positionKey, msg.sender, assetPrice_);
      count_++;
      if (count_ >= MAX_LIQUIDATIONS) {
        return count_;
      }
    }
    return count_;
  }

  /**
   * @notice liquidates a single liquidatable position
   * @param _updateData encoded pyth PriceFeed struct with verifiable pyth price information
   * @return positionKey_ bytes32 key of the position that was liquidated
   * @return executionPrice_ the price of the asset as determined by the priceManager
   * @return isSuccessful_ bool indicating if the liquidation was successful
   */
  function liquidateSingleLiquidatablePosition(
    bytes calldata _updateData
  )
    external
    nonReentrant
    returns (bytes32 positionKey_, uint256 executionPrice_, bool isSuccessful_)
  {
    bool isExecutable_;
    (executionPrice_, isExecutable_) = _getExecutionPriceAndExecutableCheck(_updateData);

    bytes32[] memory _liquidatablePositions = degenMain.getAllLiquidatablePositions(
      executionPrice_,
      block.timestamp
    );

    if (_liquidatablePositions.length == 0) {
      return (positionKey_, executionPrice_, false);
    }

    positionKey_ = _liquidatablePositions[0];
    (isSuccessful_) = _liquidatePosition(positionKey_, executionPrice_, isExecutable_);
  }

  /**
   * @notice cancels an open order
   * @param _orderIndex uint256 index of the order in the degenMain contract
   * @return marginAmount_ uint256 amount of margin that was used for the order
   */
  function cancelOpenOrder(
    uint256 _orderIndex
  ) external nonReentrant returns (uint256 marginAmount_) {
    uint256 wagerInOpenOrdersUsdc_ = wagerInOpenOrdersUsdc[_orderIndex];
    if (wagerInOpenOrdersUsdc_ > 0) {
      stableToken.transfer(msg.sender, wagerInOpenOrdersUsdc_);
      wagerInOpenOrdersUsdc[_orderIndex] = 0;
    } else {
      address wagerAsset_ = orderToWagerAsset[_orderIndex];
      uint256 wagerAmountReturn_ = amountWagerForOrder[_orderIndex];
      IERC20(wagerAsset_).transfer(msg.sender, wagerAmountReturn_);
      unchecked {
        delete amountWagerForOrder[_orderIndex];
        delete orderToWagerAsset[_orderIndex];
      }
    }
    marginAmount_ = degenMain.cancelOrder(_orderIndex, msg.sender);
    emit OpenOrderCancelled(_orderIndex, msg.sender, marginAmount_);
    return marginAmount_;
  }

  function executeOpenOrder(
    bytes calldata _updateData,
    uint256 _orderIndex
  )
    external
    onlyKeeper
    nonReentrant
    returns (bytes32 positionKey_, uint256 executionPrice_, bool _successFull)
  {
    address user_ = degenMain.returnOrderInfo(_orderIndex).player;

    bool isExecutable_;
    (executionPrice_, isExecutable_) = _getExecutionPriceAndExecutableCheck(_updateData);

    (positionKey_, _successFull) = _executeOpenOrder(
      _orderIndex,
      user_,
      executionPrice_,
      isExecutable_
    );
  }

  function executeOpenOrderBatch(
    bytes calldata _updateData,
    uint256[] calldata _orderIndexes
  )
    external
    onlyKeeper
    nonReentrant
    returns (
      bytes32[] memory positionKeys_,
      uint256[] memory executionPrices_,
      bool[] memory _successFull
    )
  {
    positionKeys_ = new bytes32[](_orderIndexes.length);
    executionPrices_ = new uint256[](_orderIndexes.length);
    _successFull = new bool[](_orderIndexes.length);

    (uint256 executionPrice_, bool isExecutable_) = _getExecutionPriceAndExecutableCheck(
      _updateData
    );

    for (uint256 i = 0; i < _orderIndexes.length; i++) {
      address user_ = degenMain.returnOrderInfo(_orderIndexes[i]).player;
      (positionKeys_[i], _successFull[i]) = _executeOpenOrder(
        _orderIndexes[i],
        user_,
        executionPrice_,
        isExecutable_
      );
      executionPrices_[i] = executionPrice_;
    }
  }

  /**
   * @notice closes an open position
   * @param _updateData encoded pyth PriceFeed struct with verifieable pyth price information
   * @param _positionKey bytes32 key of the position to be closed
   * @return executionPrice_ the price of the asset as determined by the priceManager
   * @return _successFull bool indicating if the close was successful
   */
  function closeOpenPosition(
    bytes calldata _updateData,
    bytes32 _positionKey
  ) external nonReentrant returns (uint256 executionPrice_, bool _successFull) {
    (executionPrice_, _successFull) = _closeOpenPosition(_updateData, _positionKey);
  }

  /**
   * @notice liquidates a position, if the position is profitable the liquidator will receive a portion of the profit
   * @param _updateData encoded pyth PriceFeed struct with verifieable pyth price information
   * @param _positionKey bytes32 key of the position to be liquidated
   * @return executionPrice_ the price of the asset as determined by the priceManager
   * @return _successFull bool indicating if the liquidation was successful
   */
  function liquidatePosition(
    bytes calldata _updateData,
    bytes32 _positionKey
  ) external nonReentrant returns (uint256 executionPrice_, bool _successFull) {
    bool isExecutable_;
    (executionPrice_, isExecutable_) = _getExecutionPriceAndExecutableCheck(_updateData);
    (_successFull) = _liquidatePosition(_positionKey, executionPrice_, isExecutable_);
  }

  // config functions

  function setSwap(address _swap) external {
    require(msg.sender == controller, "DegenRouter: INVALID_SENDER");
    swap = ISwap(_swap);
  }

  function setAllowedWagerAsset(address _asset, bool _allowed) external {
    require(msg.sender == controller, "DegenRouter: INVALID_SENDER");
    allowedWagerAssets[_asset] = _allowed;
    emit AllowedWagerSet(_asset, _allowed);
  }

  function setAllowedKeeper(address _keeper, bool _allowed) external {
    require(msg.sender == controller, "DegenRouter: INVALID_SENDER");
    allowedKeepers[_keeper] = _allowed;
    emit AllowedKeeperSet(_keeper, _allowed);
  }

  function setFailOnFailedExecution(bool _failOnFailedExecution) external {
    require(msg.sender == controller, "DegenRouter: INVALID_SENDER");
    failOnFailedExecution = _failOnFailedExecution;
    emit FailedOnExecutionSet(_failOnFailedExecution);
  }

  function setPriceFreshnessThreshold(uint256 _priceFreshnessThreshold) external {
    require(msg.sender == controller, "DegenRouter: INVALID_SENDER");
    require(_priceFreshnessThreshold >= minimumFreshness, "DegenRouter: price freshness too low");
    priceFreshnessThreshold = _priceFreshnessThreshold;
    emit PriceFreshnessThresholdSet(_priceFreshnessThreshold);
  }

  function changeController(address _newController) external {
    require(msg.sender == controller, "DegenRouter: INVALID_SENDER");
    controller = _newController;
    emit ControllerChanged(_newController);
  }

  // internal functions

  function _checkWagerAsset(address _wagerAsset) internal view {
    require(allowedWagerAssets[_wagerAsset], "DegenRouter: INVALID_WAGER_ASSET");
  }

  /**
   * @notice internal function that submits an order to the degenMain contract
   * @param _positionLeverage amount of leverage to use for the position, not scaled at all so 500x leverage is 500
   * @param _wagerAmount amount of margin/wager to use for the position, this is in the asset of the contract or in usdc depending on margin in stables
   * @param _minOpenPrice minimum price to open the position, note if set to 0 it means that there is no minimum price
   * @param _maxOpenPrice maximum price to open the position, note if set to 0 it means that there is no maximum price
   * @param _timestampExpired timestamp when the order expires
   * @param _isLong bool true if the user is betting on the price going up, if false the user is betting on the price going down
   * @return orderIndex_ uint256 index of the order in the degenMain contract
   */
  function _submitOrder(
    uint16 _positionLeverage,
    uint96 _wagerAmount,
    uint96 _minOpenPrice,
    uint96 _maxOpenPrice,
    uint32 _timestampExpired,
    address _wagerAsset,
    bool _isLong
  ) internal returns (uint256 orderIndex_) {
    _checkWagerAsset(_wagerAsset);

    require(_minOpenPrice <= _maxOpenPrice, "DegenRouter: min price too high");
    require(_timestampExpired > block.timestamp, "DegenRouter: expiry too soon");
    // set _maxOpenPrice that if it is 0, it is set to the max uint96, if it is non-zero it is set to the input
    _maxOpenPrice = (_maxOpenPrice == 0) ? type(uint96).max : _maxOpenPrice;
    OrderInfo memory order_;
    order_.player = msg.sender;
    order_.positionLeverage = _positionLeverage;
    order_.wagerAmount = _wagerAmount;
    order_.minOpenPrice = _minOpenPrice;
    order_.maxOpenPrice = _maxOpenPrice;
    order_.timestampExpired = _timestampExpired;
    order_.marginAsset = _wagerAsset;
    order_.isOpened = false;
    order_.isLong = _isLong;

    orderIndex_ = degenMain.submitOrder(order_);

    if (_wagerAsset == address(stableToken)) {
      // margin is in stablecoins, transfer the stablecoins to the router contract
      // only when the order is executed the stablecoins will be transferred to the poolManager as scrow
      stableToken.transferFrom(msg.sender, address(this), _wagerAmount);
      unchecked {
        // store the amount of usdc in the order (so note this is scaled 1e6)
        wagerInOpenOrdersUsdc[orderIndex_] = _wagerAmount;
      }
    } else {
      IERC20(_wagerAsset).transferFrom(msg.sender, address(this), _wagerAmount);
      // margin is in the asset of the contract, transfer the asset to the router contract
      // only when the order is executed the asset will be swapped to usdc and transferred to the poolManager as escrow
      unchecked {
        orderToWagerAsset[orderIndex_] = _wagerAsset;
        amountWagerForOrder[orderIndex_] = _wagerAmount; // note this can actually be = not += since overriding is not possible since order cannot be changed
      }
    }

    emit OpenOrderSubmitted(orderIndex_, msg.sender, _wagerAmount);

    return orderIndex_;
  }

  /**
   * @notice internal function that executes an open order that is publically executable
   * @param _orderIndex uint256 index of the order in the degenMain contract
   * @param _user address of the user  the order is executed on behalf of
   * @return positionKey_ bytes32 key of the position that was opened
   * @param _executionPrice the price of the asset as determined by the priceManager
   * @return _successFull bool indicating if the execution was successful
   */
  function _executeOpenOrder(
    uint256 _orderIndex,
    address _user,
    uint256 _executionPrice,
    bool _isExecutable
  ) internal returns (bytes32 positionKey_, bool _successFull) {
    if (_isExecutable) {
      uint256 stableAmountForMargin_;
      uint256 feesPaid_;
      stableAmountForMargin_ = wagerInOpenOrdersUsdc[_orderIndex];
      if (stableAmountForMargin_ > 0) {
        // margin is in stablecoins, so we can just use it, we delete it from the mapping so it cannot be used again
        wagerInOpenOrdersUsdc[_orderIndex] = 0;
      } else {
        address wagerAsset_ = orderToWagerAsset[_orderIndex];
        uint256 amountToSwap_ = amountWagerForOrder[_orderIndex];
        // margin is in the asset of the contract, so we need to swap it to stablecoins first with the
        IERC20(wagerAsset_).transfer(address(swap), amountToSwap_);
        (stableAmountForMargin_, feesPaid_) = swap.swapTokens(
          amountToSwap_,
          wagerAsset_,
          address(stableToken),
          address(this)
        );
        unchecked {
          delete amountWagerForOrder[_orderIndex];
          delete orderToWagerAsset[_orderIndex];
        }
      }
      // transfer the stablecoins to the poolManager
      stableToken.transfer(address(poolManager), stableAmountForMargin_);
      // in the executeOrder function in degenMain we call poolManager to register the transferred in margin in stablecoins
      positionKey_ = degenMain.executeOrder(_orderIndex, _executionPrice, stableAmountForMargin_);
      emit OpenOrderExecuted(
        positionKey_,
        _user,
        _executionPrice,
        stableAmountForMargin_,
        feesPaid_
      );
      return (positionKey_, true);
    } else {
      if (failOnFailedExecution) {
        revert("DegenRouter: price update too old");
      }
      _executionPrice = 0;
      emit OpenOrderNotExecuted(positionKey_, _user, _executionPrice);

      return (positionKey_, false);
    }
  }

  /**
   * @notice internal function that closes an open position
   * @param _updateData encoded pyth PriceFeed struct with verifieable pyth price information
   * @param _positionKey bytes32 key of the position to be closed
   * @return executionPrice_ the price of the asset as determined by the priceManager
   * @return _successFull bool indicating if the close was successful
   */
  function _closeOpenPosition(
    bytes calldata _updateData,
    bytes32 _positionKey
  ) internal returns (uint256 executionPrice_, bool _successFull) {
    bool isExecutable_;
    (executionPrice_, isExecutable_) = _getExecutionPriceAndExecutableCheck(_updateData);
    if (isExecutable_) {
      degenMain.closePosition(_positionKey, msg.sender, executionPrice_);
      emit PositionClosed(_positionKey, msg.sender, executionPrice_);
      return (executionPrice_, true);
    } else {
      if (failOnFailedExecution) {
        revert("DegenRouter: price update too old");
      }
      executionPrice_ = 0;
      emit PositionCloseFail(_positionKey, msg.sender, executionPrice_);
      return (executionPrice_, false);
    }
  }

  /**
   * @notice internal function that liquidates a position, if the position is profitable the liquidator will receive a portion of the profit
   * @param _positionKey bytes32 key of the position to be liquidated
   * @param _executionPrice the price of the asset as determined by the priceManager
   * @return _successFull bool indicating if the liquidation was successful
   */
  function _liquidatePosition(
    bytes32 _positionKey,
    uint256 _executionPrice,
    bool _isExecutable
  ) internal returns (bool _successFull) {
    if (_isExecutable) {
      degenMain.liquidatePosition(_positionKey, msg.sender, _executionPrice);
      emit PositionLiquidated(_positionKey, msg.sender, _executionPrice);
      return (true);
    } else {
      if (failOnFailedExecution) {
        revert("DegenRouter: price update too old");
      }
      _executionPrice = 0;
      emit PositionLiquidationFailed(_positionKey, msg.sender, _executionPrice);
      return (false);
    }
  }

  /**
   * @notice internal function that determines if the price update data is recent enough to be used to execute a position/order
   * @param _priceUpdateData bytes sourced from the pyth api feed, that will be used to update the price feed
   * @return executionPrice_ the price of the asset as determined by the priceManager
   * @return isExecutable_ bool indiciating if the executionPrice determined is fresh enough to be used to settle/execute an position/order
   */
  function _getExecutionPriceAndExecutableCheck(
    bytes calldata _priceUpdateData
  ) internal returns (uint256 executionPrice_, bool isExecutable_) {
    uint256 secondsSinceUpdate_;
    (executionPrice_, secondsSinceUpdate_) = priceManager.getLatestAssetPriceAndUpdate(
      _priceUpdateData
    );
    isExecutable_ = _checkPriceFreshness(secondsSinceUpdate_);
    return (executionPrice_, isExecutable_);
  }

  function _checkPriceFreshness(uint256 _ageOfPricePublish) internal view returns (bool isFresh_) {
    isFresh_ = _ageOfPricePublish <= priceFreshnessThreshold;
  }

  // VIEW FUNCTIONS

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
}

