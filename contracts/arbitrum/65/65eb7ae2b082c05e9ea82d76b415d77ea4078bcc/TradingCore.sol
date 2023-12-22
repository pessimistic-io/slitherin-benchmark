// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./FeeVault.sol";
import "./TraderFarm.sol";
import "./IRegistryCore.sol";
import "./IPool.sol";
import "./ITradingCore.sol";
import "./AbstractOracleAggregator.sol";
import "./IDistributable.sol";
import "./ITimeLock.sol";
import "./TradingCoreLib.sol";
import "./FixedPoint.sol";
import "./ERC20Fixed.sol";
import "./Errors.sol";
import "./Allowlistable.sol";
import "./OwnableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ERC20.sol";
import "./SafeCast.sol";

contract TradingCore is
  ITradingCore,
  OwnableUpgradeable,
  AccessControlUpgradeable,
  ReentrancyGuardUpgradeable,
  PausableUpgradeable,
  Allowlistable
{
  using FixedPoint for uint256;
  using FixedPoint for int256;
  using SafeCast for uint256;
  using SafeCast for int256;
  using ERC20Fixed for ERC20;

  bytes32 public constant APPROVED_ROLE = keccak256("APPROVED_ROLE");

  IRegistryCore public registry;
  IPool public liquidityPool;
  IPool public marginPool;
  IDistributable public revenuePool;
  ERC20 public baseToken;

  AbstractOracleAggregator public oracleAggregator; //settable
  TradingCoreLib public tradingCoreLib;

  TraderFarm public traderFarm;

  ITimeLock public timeLock;
  uint256 public timeLockThreshold;

  FeeVault public feeVault;

  event SetOracleAggregatorEvent(AbstractOracleAggregator oracleAggregator);
  event SetTradingCoreLibEvent(TradingCoreLib tradingCoreLib);
  event SetTraderFarmEvent(TraderFarm traderFarm);
  event SetTimeLockEvent(ITimeLock timeLock);
  event SetTimeLockThresholdEvent(uint256 timeLockThreshold);
  event SetFeeVaultEvent(FeeVault feeVault);

  function initialize(
    address _owner,
    AbstractOracleAggregator _oracleAggregator,
    ERC20 _baseToken,
    IRegistryCore _registry,
    IPool _liquidityPool,
    IPool _marginPool,
    IDistributable _revenuePool
  ) external initializer {
    __AccessControl_init();
    __Ownable_init();
    __ReentrancyGuard_init();
    __Pausable_init();
    __Allowlistable_init();

    _transferOwnership(_owner);
    _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    baseToken = _baseToken;
    liquidityPool = _liquidityPool;
    registry = _registry;
    marginPool = _marginPool;
    oracleAggregator = _oracleAggregator;
    revenuePool = _revenuePool;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  // modifiers

  modifier onlyLiquidator() {
    _require(registry.isLiquidator(msg.sender), Errors.LIQUIDATOR_ONLY);
    _;
  }

  modifier notContract() {
    require(tx.origin == msg.sender || hasRole(APPROVED_ROLE, msg.sender));
    _;
  }

  // governance functions

  function setFeeVault(FeeVault _feeVault) external onlyOwner {
    feeVault = _feeVault;
    emit SetFeeVaultEvent(feeVault);
  }

  function setTimeLockThreshold(uint256 _timeLockThreshold) external onlyOwner {
    timeLockThreshold = _timeLockThreshold;
    emit SetTimeLockThresholdEvent(timeLockThreshold);
  }

  function setTimeLock(ITimeLock _timeLock) external onlyOwner {
    timeLock = _timeLock;
    emit SetTimeLockEvent(timeLock);
  }

  function setTraderFarm(TraderFarm _traderFarm) external onlyOwner {
    traderFarm = _traderFarm;
    emit SetTraderFarmEvent(traderFarm);
  }

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

  function setOracleAggregator(
    AbstractOracleAggregator _oracleAggregator
  ) external onlyOwner {
    oracleAggregator = _oracleAggregator;
    emit SetOracleAggregatorEvent(oracleAggregator);
  }

  // priviledged functions

  function openMarketOrder(
    OpenTradeInput calldata openData,
    uint128 openPrice
  ) external whenNotPaused nonReentrant onlyRole(APPROVED_ROLE) {
    _openMarketOrder(openData, openPrice);
  }

  function openMarketOrder(
    OpenTradeInput calldata openData,
    bytes[] calldata priceData
  ) external payable whenNotPaused nonReentrant onlyRole(APPROVED_ROLE) {
    uint256 updateFee = oracleAggregator.getUpdateFee(priceData.length);
    IOracleProvider.PricePackage memory pricePackage = oracleAggregator
      .updateLatestPrice{value: updateFee}(
      openData.user,
      openData.priceId,
      priceData,
      updateFee
    );

    _openMarketOrder(
      openData,
      openData.isBuy ? pricePackage.ask : pricePackage.bid
    );
  }

  function liquidateMarketOrder(
    CloseTradeInput calldata closeData,
    bytes[] calldata priceData
  ) external nonReentrant onlyLiquidator returns (uint128) {
    IRegistry.Trade memory trade = registry.openTradeByOrderHash(
      closeData.orderHash
    );

    IOracleProvider.PricePackage memory pricePackage = oracleAggregator
      .parsePriceFeed(trade.user, trade.priceId, priceData);
    _require(
      trade.executionTime < pricePackage.publishTime,
      Errors.INVALID_TIMESTAMP
    );

    return
      _closeMarketOrder(
        closeData,
        trade.isBuy ? pricePackage.bid : pricePackage.ask,
        true
      );
  }

  // external functions

  function closeMarketOrder(
    CloseTradeInput calldata closeData,
    bytes[] calldata priceData
  )
    external
    payable
    nonReentrant
    onlyAllowlisted
    notContract
    returns (uint128 settled)
  {
    IRegistry.Trade memory trade = registry.openTradeByOrderHash(
      closeData.orderHash
    );

    _require(
      trade.user == msg.sender || hasRole(APPROVED_ROLE, msg.sender),
      Errors.USER_SENDER_MISMATCH
    );
    _require(
      trade.executionBlock < block.number.sub(registry.minBlockGap()),
      Errors.INVALID_TIMESTAMP
    ); // at least one block

    uint256 updateFee = oracleAggregator.getUpdateFee(priceData.length);
    IOracleProvider.PricePackage memory pricePackage = oracleAggregator
      .updateLatestPrice{value: updateFee}(
      trade.user,
      trade.priceId,
      priceData,
      updateFee
    );

    settled = _closeMarketOrder(
      closeData,
      trade.isBuy ? pricePackage.bid : pricePackage.ask,
      false
    );
  }

  function addMargin(
    bytes32 orderHash,
    bytes[] calldata priceData,
    uint128 margin
  ) external payable whenNotPaused nonReentrant onlyAllowlisted notContract {
    IRegistry.Trade memory t = registry.openTradeByOrderHash(orderHash);

    _require(
      t.user == msg.sender || hasRole(APPROVED_ROLE, msg.sender),
      Errors.USER_SENDER_MISMATCH
    );
    _require(
      t.executionBlock < block.number.sub(registry.minBlockGap()),
      Errors.INVALID_TIMESTAMP
    ); // at least one block

    uint256 updateFee = oracleAggregator.getUpdateFee(priceData.length);
    IOracleProvider.PricePackage memory pricePackage = oracleAggregator
      .updateLatestPrice{value: updateFee}(
      t.user,
      t.priceId,
      priceData,
      updateFee
    );

    IRegistry.Trade memory trade = registry.updateTrade(
      orderHash,
      t.isBuy ? pricePackage.bid : pricePackage.ask,
      margin,
      true,
      liquidityPool.getBaseBalance()
    );

    registry.updateOpenOrder(orderHash, trade);
    baseToken.transferFromFixed(msg.sender, address(marginPool), margin);

    // audit(S): UNW-1
    emit UpdateOpenOrderEvent(
      msg.sender,
      orderHash,
      trade,
      OnUpdateTrade(true, margin),
      registry.onOrderUpdate(orderHash)
    );
  }

  function removeMargin(
    bytes32 orderHash,
    bytes[] calldata priceData,
    uint128 margin
  ) external payable whenNotPaused nonReentrant onlyAllowlisted notContract {
    IRegistry.Trade memory t = registry.openTradeByOrderHash(orderHash);

    _require(
      t.user == msg.sender || hasRole(APPROVED_ROLE, msg.sender),
      Errors.USER_SENDER_MISMATCH
    );
    _require(
      t.executionBlock < block.number.sub(registry.minBlockGap()),
      Errors.INVALID_TIMESTAMP
    ); // at least one block

    uint256 updateFee = oracleAggregator.getUpdateFee(priceData.length);
    IOracleProvider.PricePackage memory pricePackage = oracleAggregator
      .updateLatestPrice{value: updateFee}(
      t.user,
      t.priceId,
      priceData,
      updateFee
    );

    IRegistry.Trade memory trade = registry.updateTrade(
      orderHash,
      t.isBuy ? pricePackage.bid : pricePackage.ask,
      margin,
      false,
      liquidityPool.getBaseBalance()
    );

    registry.updateOpenOrder(orderHash, trade);
    marginPool.transferBase(msg.sender, margin);

    // audit(S): UNW-1
    emit UpdateOpenOrderEvent(
      msg.sender,
      orderHash,
      trade,
      OnUpdateTrade(false, margin),
      registry.onOrderUpdate(orderHash)
    );
  }

  function updateStop(
    bytes32 orderHash,
    bytes[] calldata priceData,
    uint128 profitTarget,
    uint128 stopLoss
  ) external payable whenNotPaused onlyAllowlisted notContract {
    IRegistry.Trade memory t = registry.openTradeByOrderHash(orderHash);
    _require(t.user == msg.sender, Errors.USER_SENDER_MISMATCH);
    _require(
      t.executionBlock < block.number.sub(registry.minBlockGap()),
      Errors.INVALID_TIMESTAMP
    ); // at least one block
    IOracleProvider.PricePackage memory pricePackage;
    {
      uint256 updateFee = oracleAggregator.getUpdateFee(priceData.length);
      pricePackage = oracleAggregator.updateLatestPrice{value: updateFee}(
        t.user,
        t.priceId,
        priceData,
        updateFee
      );
    }
    IRegistry.Trade memory trade = registry.updateStop(
      orderHash,
      t.isBuy ? pricePackage.bid : pricePackage.ask,
      profitTarget,
      stopLoss
    );
    registry.updateOpenOrder(orderHash, trade);

    // audit(S): UNW-1
    emit UpdateOpenOrderEvent(
      msg.sender,
      orderHash,
      trade,
      OnUpdateTrade(true, 0),
      registry.onOrderUpdate(orderHash)
    );
  }

  // internal functions

  function _openMarketOrder(
    OpenTradeInput memory openData,
    uint128 openPrice
  ) internal {
    (IRegistry.Trade memory trade, IFee.Fee memory _fee) = tradingCoreLib
      .canOpenMarketOrder(
        registry,
        openData,
        openPrice,
        liquidityPool.getBaseBalance()
      );

    bytes32 orderHash = registry.openMarketOrder(trade);

    uint256 netFee = uint256(_fee.fee).sub(_fee.referralFee);
    uint256 netFeeRebate = netFee.mulDown(registry.feeFactor());

    // net margin
    baseToken.transferFromFixed(msg.sender, address(marginPool), trade.margin);
    // reserve fund
    baseToken.transferFromFixed(msg.sender, owner(), netFee.sub(netFeeRebate));
    // rebates
    baseToken.transferFromFixed(msg.sender, address(this), netFeeRebate);

    // ULP share of rebates
    uint256 netFeeRebateLP = netFeeRebate.mulDown(registry.netFeeRebateLP());
    baseToken.transferFixed(address(liquidityPool), netFeeRebateLP);

    // esUNW share of rebates
    // baseToken.approveFixed(
    //   address(revenuePool),
    //   netFeeRebate.sub(netFeeRebateLP)
    // );
    // revenuePool.transferIn(netFeeRebate.sub(netFeeRebateLP));
    baseToken.approveFixed(address(feeVault), netFeeRebate.sub(netFeeRebateLP));
    feeVault.add(netFeeRebate.sub(netFeeRebateLP));

    // traderFarm.stake(trade.user, uint256(trade.margin).mulDown(trade.leverage));

    if (_fee.referrer != address(0)) {
      baseToken.transferFromFixed(msg.sender, _fee.referrer, _fee.referralFee);
    }

    emit OpenMarketOrderEvent(
      openData.user,
      orderHash,
      trade,
      _fee,
      registry.onOrderUpdate(orderHash)
    );
  }

  function _closeMarketOrder(
    CloseTradeInput memory closeData,
    uint256 closePrice,
    bool isLiquidator
  ) internal returns (uint128) {
    _require(
      isLiquidator
        ? closeData.closePercent == 1e18
        : (closeData.closePercent > 0 && closeData.closePercent <= 1e18),
      Errors.INVALID_CLOSE_PERCENT
    );

    IRegistry.Trade memory trade = registry.openTradeByOrderHash(
      closeData.orderHash
    );

    _require(
      trade.executionBlock < block.number.sub(registry.minBlockGap()),
      Errors.INVALID_TIMESTAMP
    );

    OnCloseTrade memory onCloseTrade = tradingCoreLib.closeTrade(
      registry,
      closeData.orderHash,
      closeData.closePercent,
      closePrice.toUint128()
    );

    if (isLiquidator && !(onCloseTrade.isLiquidated || onCloseTrade.isStop)) {
      _revert(Errors.CANNOT_LIQUIDATE);
    }

    _require(
      trade.isBuy
        ? closeData.limitPrice <= onCloseTrade.closeNet
        : closeData.limitPrice >= onCloseTrade.closeNet,
      Errors.SLIPPAGE_EXCEEDS_LIMIT
    );

    registry.closeMarketOrder(
      closeData.orderHash,
      uint256(closeData.closePercent).toUint64()
    );

    AfterCloseTrade memory afterCloseTrade;
    (onCloseTrade, afterCloseTrade) = tradingCoreLib.onAfterCloseTrade(
      registry,
      trade,
      closeData.closePercent,
      isLiquidator,
      onCloseTrade
    );

    marginPool.transferBase(
      address(liquidityPool),
      uint256(trade.margin).mulDown(closeData.closePercent)
    );

    {
      uint256 netFee = uint256(afterCloseTrade.fees.fee).sub(
        afterCloseTrade.fees.referralFee
      );

      // reserve fund
      uint256 netFeeRebate = netFee.mulDown(registry.feeFactor());
      liquidityPool.transferBase(owner(), netFee.sub(netFeeRebate));

      // back to ULP
      uint256 netFeeRebateLP = netFeeRebate.mulDown(registry.netFeeRebateLP());

      // the rest
      uint256 netFeeRebateRev = netFeeRebate.sub(netFeeRebateLP);
      liquidityPool.transferBase(address(this), netFeeRebateRev);
      // baseToken.approveFixed(address(revenuePool), netFeeRebateRev);
      // revenuePool.transferIn(netFeeRebateRev);
      baseToken.approveFixed(address(feeVault), netFeeRebateRev);
      feeVault.add(netFeeRebateRev);

      if (afterCloseTrade.fees.referrer != address(0)) {
        liquidityPool.transferBase(
          afterCloseTrade.fees.referrer,
          afterCloseTrade.fees.referralFee
        );
      }
    }

    if (afterCloseTrade.liquidationFee >= 0) {
      liquidityPool.transferBase(msg.sender, afterCloseTrade.liquidationFee);
    }

    if (afterCloseTrade.settled >= timeLockThreshold) {
      liquidityPool.transferBase(address(this), afterCloseTrade.settled);
      baseToken.approveFixed(address(timeLock), afterCloseTrade.settled);
      timeLock.createAgreement(
        address(baseToken),
        afterCloseTrade.settled,
        trade.user,
        TimeLockDataTypes.AgreementContext.TRADING_CORE
      );
    } else {
      liquidityPool.transferBase(trade.user, afterCloseTrade.settled);
    }

    // traderFarm.stake(
    //   trade.user,
    //   uint256(trade.margin).mulDown(closeData.closePercent).mulDown(
    //     trade.leverage
    //   )
    // );

    emit CloseMarketOrderEvent(
      msg.sender,
      closeData.orderHash,
      closeData.closePercent,
      trade,
      onCloseTrade,
      afterCloseTrade,
      closeData.closePercent < 1e18
        ? registry.onOrderUpdate(closeData.orderHash)
        : IRegistryCore.OnOrderUpdate(
          IRegistryCore.SignedBalance(0, 0),
          0,
          IRegistryCore.AccruedFee(0, 0, 0)
        )
    );

    return afterCloseTrade.settled;
  }
}

