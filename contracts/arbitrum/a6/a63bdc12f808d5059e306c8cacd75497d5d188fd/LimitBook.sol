// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./ITradingCore.sol";
import "./ILimitBook.sol";
import "./ISwapRouter.sol";
import "./IPool.sol";
import "./OnlyDelegateCall.sol";
import "./Errors.sol";
import "./ERC20Fixed.sol";
import "./TradingCoreLib.sol";
import "./FixedPoint.sol";
import "./Allowlistable.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ERC20.sol";
import "./SafeCast.sol";

contract LimitBook is
  ILimitBook,
  OwnableUpgradeable,
  ReentrancyGuardUpgradeable,
  PausableUpgradeable,
  OnlyDelegateCall,
  Allowlistable
{
  using FixedPoint for uint256;
  using SafeCast for uint256;
  using ERC20Fixed for ERC20;

  address baseToken;
  ITradingCore tradingCore;
  IRegistryCore registry;
  AbstractOracleAggregator oracleAggregator;

  TradingCoreLib tradingCoreLib;

  mapping(address => mapping(bytes32 => mapping(uint256 => bytes32)))
    public openLimitOrders;
  mapping(bytes32 => IRegistry.Trade) internal _openLimitOrderByOrderHash;
  mapping(address => mapping(bytes32 => uint128))
    public openLimitOrdersPerPriceIdCount;
  mapping(address => uint128) public openLimitOrdersPerUserCount;

  event SetTradingCoreLibEvent(TradingCoreLib tradingCoreLib);

  function initialize(
    address _owner,
    ITradingCore _tradingCore,
    IRegistryCore _registryCore
  ) external initializer {
    __Ownable_init();
    __ReentrancyGuard_init();
    __Pausable_init();
    __Allowlistable_init();
    _transferOwnership(_owner);
    tradingCore = _tradingCore;
    baseToken = address(tradingCore.baseToken());
    registry = _registryCore;
    oracleAggregator = tradingCore.oracleAggregator();
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  modifier onlyLiquidator() {
    _require(registry.isLiquidator(msg.sender), Errors.LIQUIDATOR_ONLY);
    _;
  }

  modifier onlyApprovedPriceId(bytes32 priceId) {
    _require(registry.approvedPriceId(priceId), Errors.APPROVED_PRICE_ID_ONLY);
    _;
  }

  modifier notContract() {
    require(tx.origin == msg.sender);
    _;
  }

  // governance functions

  function setTradingCoreLib(
    TradingCoreLib _tradingCoreLib
  ) external onlyOwner {
    tradingCoreLib = _tradingCoreLib;
    emit SetTradingCoreLibEvent(tradingCoreLib);
  }

  function onAllowlist() external onlyOwner {
    _onAllowlist();
  }

  function offAllowlist() external onlyOwner {
    _offAllowlist();
  }

  function addAllowlist(address[] memory _allowed) external onlyOwner {
    _addAllowlist(_allowed);
  }

  function removeAllowlist(address[] memory _removed) external onlyOwner {
    _removeAllowlist(_removed);
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

  // external functions

  function openLimitOrderByOrderHash(
    bytes32 orderHash
  ) public view returns (IRegistry.Trade memory t) {
    t = _openLimitOrderByOrderHash[orderHash];
    _require(t.user != address(0x0), Errors.ORDER_NOT_FOUND);
  }

  function canOpenLimitOrder(
    OpenTradeInput memory openData
  ) public view returns (IRegistry.Trade memory trade) {
    _require(
      ERC20(baseToken).balanceOfFixed(msg.sender) >= openData.margin,
      Errors.INVALID_MARGIN
    );

    trade = tradingCoreLib.createTrade(
      registry,
      openData,
      openData.limitPrice,
      0,
      0,
      tradingCore.liquidityPool().getBaseBalance()
    );
    trade.user = msg.sender;
  }

  function openLimitOrder(
    OpenTradeInput calldata openData
  )
    external
    whenNotPaused
    onlyApprovedPriceId(openData.priceId)
    nonReentrant
    onlyAllowlisted
    notContract
  {
    _openLimitOrder(openData);
  }

  function closeLimitOrder(
    bytes32 orderHash,
    uint64 closePercent
  ) external override nonReentrant onlyAllowlisted notContract {
    _require(
      closePercent > 0 && closePercent <= 1e18,
      Errors.INVALID_CLOSE_PERCENT
    );
    IRegistry.Trade memory trade = openLimitOrderByOrderHash(orderHash);
    _require(msg.sender == trade.user, Errors.USER_SENDER_MISMATCH);
    _closeLimitOrder(orderHash, closePercent);
    ERC20(baseToken).transferFixed(
      msg.sender,
      uint256(trade.margin).mulDown(closePercent)
    );
    if (closePercent == 1e18) {
      emit CloseLimitOrderEvent(
        tx.origin,
        orderHash,
        trade.user,
        trade.priceId
      );
    } else {
      emit PartialCloseLimitOrderEvent(
        tx.origin,
        orderHash,
        trade,
        closePercent
      );
    }
  }

  function canExecuteLimitOrder(
    bytes32 orderHash,
    bytes[] calldata priceData
  )
    public
    view
    returns (
      IRegistry.Trade memory t,
      OpenTradeInput memory openData,
      uint128 executionPrice
    )
  {
    t = openLimitOrderByOrderHash(orderHash);

    IOracleProvider.PricePackage memory pricePackage = oracleAggregator
      .parsePriceFeed(t.user, t.priceId, priceData);
    _require(
      t.executionTime < pricePackage.publishTime,
      Errors.INVALID_TIMESTAMP
    );
    // _require(t.executionBlock < block.number, Errors.INVALID_TIMESTAMP); // at least one block

    // actual execution is at worst at openPrice, and we don't deduct fee
    // so this is more conservative than actual slippage
    uint256 expectedSlippage = registry.getSlippage(
      t.priceId,
      t.isBuy,
      t.openPrice,
      uint256(t.leverage).mulDown(t.margin).toUint128()
    );
    uint256 expectedExecution = t.isBuy
      ? uint256(t.openPrice).sub(expectedSlippage)
      : uint256(t.openPrice).add(expectedSlippage);
    _require(
      t.isBuy
        ? pricePackage.ask <= expectedExecution
        : pricePackage.bid >= expectedExecution,
      Errors.CANNOT_EXECUTE_LIMIT
    );

    openData = OpenTradeInput(
      t.priceId,
      t.user,
      t.isBuy,
      t.margin,
      t.leverage,
      t.profitTarget,
      t.stopLoss,
      t.openPrice
    );
    executionPrice = t.isBuy ? pricePackage.ask : pricePackage.bid;
  }

  function executeLimitOrder(
    bytes32 orderHash,
    bytes[] calldata priceData
  ) external override whenNotPaused nonReentrant onlyLiquidator {
    (
      IRegistry.Trade memory t,
      OpenTradeInput memory openData,
      uint128 executionPrice
    ) = canExecuteLimitOrder(orderHash, priceData);

    _closeLimitOrder(orderHash, 1e18);
    ERC20(baseToken).approveFixed(address(tradingCore), t.margin);
    tradingCore.openMarketOrder(openData, executionPrice);
    emit ExecuteLimitOrderEvent(tx.origin, orderHash, t.user, t.priceId);
  }

  function updateLimitStop(
    bytes32 orderHash,
    uint256 profitTarget,
    uint256 stopLoss
  ) external whenNotPaused onlyAllowlisted notContract {
    IRegistry.Trade memory trade = openLimitOrderByOrderHash(orderHash);
    _require(
      trade.executionBlock < block.number.sub(registry.minBlockGap()),
      Errors.INVALID_TIMESTAMP
    ); // at least one block
    _require(
      stopLoss == 0 ||
        (
          trade.isBuy
            ? stopLoss.add(registry.minIncrement()) < trade.openPrice
            : stopLoss.sub(registry.minIncrement()) > trade.openPrice
        ),
      Errors.INVALID_STOP_LOSS
    );
    _require(
      profitTarget == 0 ||
        (
          trade.isBuy
            ? profitTarget.sub(registry.minIncrement()) > trade.openPrice
            : profitTarget.add(registry.minIncrement()) < trade.openPrice
        ),
      Errors.INVALID_PROFIT_TARGET
    );

    trade.stopLoss = stopLoss.toUint128();
    trade.profitTarget = profitTarget.toUint128();
    trade.executionTime = uint256(block.timestamp).toUint32();
    trade.executionBlock = uint256(block.number).toUint32();

    _updateOpenLimitOrder(orderHash, trade);
    emit UpdateOpenLimitOrderEvent(tx.origin, orderHash, trade);
  }

  // internal functions

  function _openLimitOrder(OpenTradeInput calldata openData) internal {
    IRegistry.Trade memory trade = canOpenLimitOrder(openData);
    ERC20(baseToken).transferFromFixed(
      msg.sender,
      address(this),
      openData.margin
    );
    bytes32 orderHash = _createLimitOrder(trade);
    emit OpenLimitOrderEvent(tx.origin, orderHash, trade);
  }

  function _createLimitOrder(
    IRegistry.Trade memory trade
  ) internal returns (bytes32) {
    openLimitOrdersPerPriceIdCount[trade.user][trade.priceId]++;
    trade.salt = openLimitOrdersPerPriceIdCount[trade.user][trade.priceId];

    bytes32 orderHash = keccak256(abi.encode(trade));

    openLimitOrdersPerUserCount[trade.user]++;
    openLimitOrders[trade.user][trade.priceId][trade.salt] = orderHash;
    _openLimitOrderByOrderHash[orderHash] = trade;
    return orderHash;
  }

  function _updateOpenLimitOrder(
    bytes32 orderHash,
    IRegistry.Trade memory trade
  ) internal {
    IRegistry.Trade memory t = openLimitOrderByOrderHash(orderHash);
    _require(t.user == trade.user, Errors.TRADER_OWNER_MISMATCH);
    _openLimitOrderByOrderHash[orderHash] = trade;
  }

  function _closeLimitOrder(bytes32 orderHash, uint256 closePercent) internal {
    IRegistry.Trade memory t = openLimitOrderByOrderHash(orderHash);
    uint256 closeMargin = uint256(t.margin).mulDown(closePercent);

    if (closePercent == 1e18) {
      openLimitOrdersPerPriceIdCount[t.user][t.priceId]--;
      openLimitOrdersPerUserCount[t.user]--;
      delete openLimitOrders[t.user][t.priceId][t.salt];
      delete _openLimitOrderByOrderHash[orderHash];
    } else {
      t.margin -= closeMargin.toUint128();
      _openLimitOrderByOrderHash[orderHash] = t;
    }
  }
}

