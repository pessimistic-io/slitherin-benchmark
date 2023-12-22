// SPDX-License-Identifier: BUSL-1.1

import "./IRegistryCore.sol";
import "./AbstractRegistry.sol";

pragma solidity ^0.8.17;

contract RegistryCore is AbstractRegistry, IRegistryCore {
  using SafeCast for uint256;
  using SafeCast for int256;
  using FixedPoint for uint256;
  using FixedPoint for int256;

  IFee internal fees;

  mapping(bytes32 => uint128) public fundingFeePerPriceId; //deprecated
  mapping(bytes32 => uint128) public rolloverFeePerPriceId;

  mapping(bytes32 => SignedBalance) internal _longFundingFeePerPriceId; //deprecated
  mapping(bytes32 => SignedBalance) internal _shortFundingFeePerPriceId; //deprecated

  mapping(bytes32 => int128) internal _fundingFeeBaseByOrderHash; //deprecated
  mapping(bytes32 => AccruedFee) internal _accruedFeeByOrderHash;

  mapping(bytes32 => uint128) public maxTotalLongPerPriceId;
  mapping(bytes32 => uint128) public maxTotalShortPerPriceId;

  uint64 public netFeeRebateLP;
  uint256 public minIncrement;
  uint256 public minBlockGap;

  mapping(address => mapping(uint128 => bytes32))
    public openTradeOrderHashesPerUser;

  event SetFeesEvent(address fees);
  event SetFundingFeeEvent(bytes32 priceId, uint256 fundingFee);
  event SetRolloverFeeEvent(bytes32 priceId, uint256 rolloverFee);
  event SetMaxTotalLongPerPriceId(bytes32 priceId, uint256 _maxLong);
  event SetMaxTotalShortPerPriceId(bytes32 priceId, uint256 _maxShort);
  event SetNetFeeRabateLP(uint256 _fee);
  event SetMinIncrementEvent(uint256 _minIncrement);
  event SetMinBlockGapEvent(uint256 _minBlockGap);

  function initialize(
    address _owner,
    uint16 _maxOpenTradesPerPriceId,
    uint16 _maxOpenTradesPerUser,
    uint128 _maxMarginPerUser,
    uint128 _minPositionPerTrade,
    uint64 _liquidationPenalty,
    uint128 _maxPercentagePnLFactor,
    uint128 _stopFee,
    IFee _fees
  ) external initializer {
    __AbstractRegistry_init(
      _owner,
      _maxOpenTradesPerPriceId,
      _maxOpenTradesPerUser,
      _maxMarginPerUser,
      _minPositionPerTrade,
      _liquidationPenalty,
      _maxPercentagePnLFactor,
      _stopFee,
      0
    );
    fees = _fees;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  // external functions

  function getFee() external view override returns (uint256) {
    _revert(Errors.UNIMPLEMENTED);
  }

  function getOpenFee(
    address _user
  ) external view override returns (IFee.Fee memory) {
    return fees.getOpenFee(_user);
  }

  function getCloseFee(
    address _user
  ) external view override returns (IFee.Fee memory) {
    return fees.getCloseFee(_user);
  }

  function getAccumulatedFee(
    bytes32 orderHash,
    uint64 closePercent
  ) external view override returns (int128 fundingFee, uint128 rolloverFee) {
    _require(closePercent <= 1e18, Errors.INVALID_CLOSE_PERCENT);
    Trade memory trade = _openTradeByOrderHash(orderHash);
    (, AccruedFee memory accruedFee) = _getAccumulatedFee(
      orderHash,
      trade.priceId,
      trade.isBuy,
      trade.leverage,
      trade.margin
    );
    fundingFee = int256(accruedFee.fundingFee).mulDown(closePercent).toInt128();
    rolloverFee = uint256(accruedFee.rolloverFee)
      .mulDown(closePercent)
      .toUint128();
  }

  function longFundingFeePerPriceId(
    bytes32 priceId
  ) external view returns (SignedBalance memory) {
    return _longFundingFeePerPriceId[priceId];
  }

  function shortFundingFeePerPriceId(
    bytes32 priceId
  ) external view returns (SignedBalance memory) {
    return _shortFundingFeePerPriceId[priceId];
  }

  function fundingFeeBaseByOrderHash(
    bytes32 orderHash
  ) external view returns (int256) {
    return _fundingFeeBaseByOrderHash[orderHash];
  }

  function accruedFeeByOrderHash(
    bytes32 orderHash
  ) external view returns (AccruedFee memory) {
    return _accruedFeeByOrderHash[orderHash];
  }

  function onOrderUpdate(
    bytes32 orderHash
  ) external view override returns (OnOrderUpdate memory _onOrderUpdate) {
    Trade memory trade = _openTradeByOrderHash(orderHash);
    _onOrderUpdate.feeBalance = trade.isBuy
      ? _longFundingFeePerPriceId[trade.priceId]
      : _shortFundingFeePerPriceId[trade.priceId];
    _onOrderUpdate.feeBase = _fundingFeeBaseByOrderHash[orderHash];
    (, _onOrderUpdate.accruedFee) = _getAccumulatedFee(
      orderHash,
      trade.priceId,
      trade.isBuy,
      trade.leverage,
      trade.margin
    );
  }

  function updateTrade(
    bytes32 orderHash,
    uint128 closePrice,
    uint128 margin,
    bool isAdd,
    uint256 liquidityBalance
  ) external view override returns (Trade memory trade) {
    return _updateTrade(orderHash, closePrice, margin, isAdd, liquidityBalance);
  }

  function updateStop(
    bytes32 orderHash,
    uint128 closePrice,
    uint128 profitTarget,
    uint128 stopLoss
  ) external view returns (Trade memory trade) {
    return _updateStop(orderHash, closePrice, profitTarget, stopLoss);
  }

  function openTradeOrderHashesByUser(
    address user
  ) external view returns (bytes32[] memory orderHashes) {
    uint128 count = openTradesPerUserCount[user];
    orderHashes = new bytes32[](count);
    for (uint128 i = 0; i < count; ++i) {
      orderHashes[i] = openTradeOrderHashesPerUser[user][i];
    }
  }

  // governance functions

  function setNetFeeRabateLP(uint64 _netFeeRebateLP) external onlyOwner {
    _require(
      _netFeeRebateLP >= 0 && _netFeeRebateLP <= 1e18,
      Errors.INVALID_FEE_FACTOR
    );
    netFeeRebateLP = _netFeeRebateLP;
    emit SetNetFeeRabateLP(netFeeRebateLP);
  }

  function setMaxTotalLongPerPriceId(
    bytes32 priceId,
    uint128 _maxLong
  ) external onlyOwner {
    maxTotalLongPerPriceId[priceId] = _maxLong;
    emit SetMaxTotalLongPerPriceId(priceId, _maxLong);
  }

  function setMaxTotalShortPerPriceId(
    bytes32 priceId,
    uint128 _maxShort
  ) external onlyOwner {
    maxTotalShortPerPriceId[priceId] = _maxShort;
    emit SetMaxTotalShortPerPriceId(priceId, _maxShort);
  }

  function setFees(IFee _fees) external onlyOwner {
    fees = _fees;
    emit SetFeesEvent(address(fees));
  }

  function setFundingFeePerPriceId(
    bytes32 priceId,
    uint128 _fundingFee
  ) external onlyOwner {
    fundingFeePerPriceId[priceId] = _fundingFee;
    emit SetFundingFeeEvent(priceId, _fundingFee);
  }

  function setRolloverFeePerPriceId(
    bytes32 priceId,
    uint128 _rolloverFee
  ) external onlyOwner {
    rolloverFeePerPriceId[priceId] = _rolloverFee;
    emit SetRolloverFeeEvent(priceId, _rolloverFee);
  }

  function setMinIncrement(uint256 _minIncrement) external onlyOwner {
    minIncrement = _minIncrement;
    emit SetMinIncrementEvent(minIncrement);
  }

  function setMinBlockGap(uint256 _minBlockGap) external onlyOwner {
    minBlockGap = _minBlockGap;
    emit SetMinBlockGapEvent(minBlockGap);
  }

  // privilidged functions

  function openMarketOrder(
    Trade memory trade
  )
    external
    override(IRegistry, AbstractRegistry)
    onlyRole(APPROVED_ROLE)
    onlyApprovedPriceId(trade.priceId)
    returns (bytes32)
  {
    salt++;
    trade.salt = salt;
    bytes32 orderHash = keccak256(abi.encode(trade));
    openTradesPerPriceIdCount[trade.user][trade.priceId]++;
    _addOrderHashToOpenTrades(trade.user, orderHash);
    totalMarginPerUser[trade.user] += trade.margin;

    _accruedFeeByOrderHash[orderHash].lastUpdate = trade.executionBlock;

    _updateFundingFeeBalance(
      orderHash,
      trade.priceId,
      trade.isBuy,
      uint128(0),
      uint128(0),
      trade.leverage,
      trade.margin
    );

    // audit(B): L05
    minCollateral += uint256(trade.margin)
      .mulDown(trade.maxPercentagePnL)
      .toUint128();

    __openTradeByOrderHash[orderHash] = trade;

    return orderHash;
  }

  function closeMarketOrder(
    bytes32 orderHash,
    uint64 closePercent
  ) external override(AbstractRegistry, IRegistry) onlyRole(APPROVED_ROLE) {
    Trade memory t = _openTradeByOrderHash(orderHash);
    uint256 closeMargin = uint256(t.margin).mulDown(closePercent);

    totalMarginPerUser[t.user] = uint256(totalMarginPerUser[t.user])
      .sub(closeMargin)
      .toUint128();
    minCollateral -= uint256(closeMargin)
      .mulDown(uint256(t.maxPercentagePnL))
      .toUint128();

    _updateFundingFeeBalance(
      orderHash,
      t.priceId,
      t.isBuy,
      t.leverage,
      t.margin,
      t.leverage,
      uint256(t.margin).sub(closeMargin).toUint128()
    );

    if (closePercent == 1e18) {
      openTradesPerPriceIdCount[t.user][t.priceId]--;
      _removeOrderHashFromOpenTrades(t.user, orderHash);
      delete __openTradeByOrderHash[orderHash];
      delete _fundingFeeBaseByOrderHash[orderHash];
      delete _accruedFeeByOrderHash[orderHash];
    } else {
      t.margin -= closeMargin.toUint128();
      __openTradeByOrderHash[orderHash] = t;
    }
  }

  function updateOpenOrder(
    bytes32 orderHash,
    Trade memory trade
  ) external override(AbstractRegistry, IRegistry) onlyRole(APPROVED_ROLE) {
    Trade memory t = __openTradeByOrderHash[orderHash];

    _require(t.user == trade.user, Errors.TRADER_OWNER_MISMATCH);
    _require(t.priceId == trade.priceId, Errors.PRICE_ID_MISMATCH);
    _require(t.isBuy == trade.isBuy, Errors.TRADE_DIRECTION_MISMATCH);
    // audit(M): lack of check of salt
    _require(t.salt == trade.salt, Errors.TRADE_SALT_MISMATCH);

    _updateFundingFeeBalance(
      orderHash,
      t.priceId,
      t.isBuy,
      t.leverage,
      t.margin,
      trade.leverage,
      trade.margin
    );

    totalMarginPerUser[trade.user] = uint256(totalMarginPerUser[trade.user])
      .sub(t.margin)
      .add(trade.margin)
      .toUint128();
    minCollateral -= uint256(t.margin).mulDown(t.maxPercentagePnL).toUint128();
    // audit(B): M02, L05
    minCollateral += uint256(trade.margin)
      .mulDown(trade.maxPercentagePnL)
      .toUint128();

    __openTradeByOrderHash[orderHash] = trade;
  }

  // internal functions

  function _addOrderHashToOpenTrades(address user, bytes32 orderHash) internal {
    openTradeOrderHashesPerUser[user][openTradesPerUserCount[user]] = orderHash;
    openTradesPerUserCount[user]++;
  }

  function _removeOrderHashFromOpenTrades(
    address user,
    bytes32 orderHash
  ) internal {
    uint128 tradeCount = openTradesPerUserCount[user];

    uint128 index = tradeCount;
    for (uint128 i = 0; i < tradeCount; ++i) {
      if (openTradeOrderHashesPerUser[user][i] == orderHash) {
        index = i;
        break;
      }
    }

    bool isNotFound = index >= tradeCount;
    if (isNotFound) return;

    if (index != tradeCount - 1) {
      // swap with last element
      openTradeOrderHashesPerUser[user][index] = openTradeOrderHashesPerUser[
        user
      ][tradeCount - 1];
    }
    // delete last element
    delete openTradeOrderHashesPerUser[user][tradeCount - 1];
    openTradesPerUserCount[user]--;
  }

  function _updateFundingFeeBalance(
    bytes32 orderHash,
    bytes32 priceId,
    bool isBuy,
    uint128 oldLeverage,
    uint128 oldMargin,
    uint128 newLeverage,
    uint128 newMargin
  ) internal {
    (, AccruedFee memory _accruedFee) = _getAccumulatedFee(
      orderHash,
      priceId,
      isBuy,
      oldLeverage,
      oldMargin
    );

    // uint256 _totalPosition = isBuy
    //   ? totalLongPerPriceId[priceId]
    //   : totalShortPerPriceId[priceId];

    // // simulate out
    // _fundingFee.balance = int256(_fundingFee.balance)
    //   .sub(_accruedFee.fundingFee)
    //   .add(_accruedFeeByOrderHash[orderHash].fundingFee)
    //   .sub(_fundingFeeBaseByOrderHash[orderHash])
    //   .toInt128();

    // _totalPosition = _totalPosition.sub(
    //   uint256(oldLeverage).mulDown(oldMargin)
    // );

    if (uint256(oldLeverage).mulDown(oldMargin) > 0) {
      uint256 ratio = uint256(newLeverage)
        .mulDown(newMargin)
        .divDown(oldLeverage)
        .divDown(oldMargin);
      // _accruedFee.fundingFee = int256(_accruedFee.fundingFee)
      //   .mulDown(ratio)
      //   .toInt128();
      _accruedFee.rolloverFee = uint256(_accruedFee.rolloverFee)
        .mulDown(ratio)
        .toUint128();
    }

    // // simulate in
    // _fundingFeeBaseByOrderHash[orderHash] = _totalPosition > 0
    //   ? int256(_fundingFee.balance)
    //     .mulDown(newLeverage)
    //     .mulDown(newMargin)
    //     .divDown(_totalPosition)
    //     .toInt128()
    //   : _fundingFee.balance;

    // _fundingFee.balance = int256(_fundingFee.balance)
    //   .add(_fundingFeeBaseByOrderHash[orderHash])
    //   .toInt128();
    // _totalPosition = _totalPosition.add(
    //   uint256(newLeverage).mulDown(newMargin)
    // );

    _accruedFeeByOrderHash[orderHash] = _accruedFee;

    // if (isBuy) {
    //   _longFundingFeePerPriceId[priceId] = _fundingFee;
    //   _shortFundingFeePerPriceId[priceId] = _getLatestFundingFeeBalance(
    //     _shortFundingFeePerPriceId[priceId],
    //     totalShortPerPriceId[priceId],
    //     totalLongPerPriceId[priceId],
    //     fundingFeePerPriceId[priceId]
    //   );
    //   totalLongPerPriceId[priceId] = _totalPosition.toUint128();
    // } else {
    //   _shortFundingFeePerPriceId[priceId] = _fundingFee;
    //   _longFundingFeePerPriceId[priceId] = _getLatestFundingFeeBalance(
    //     _longFundingFeePerPriceId[priceId],
    //     totalLongPerPriceId[priceId],
    //     totalShortPerPriceId[priceId],
    //     fundingFeePerPriceId[priceId]
    //   );
    //   totalShortPerPriceId[priceId] = _totalPosition.toUint128();
    // }
  }

  // function _getLatestFundingFeeBalance(
  //   SignedBalance memory fundingFee,
  //   uint256 totalPositionM,
  //   uint256 totalPositionT,
  //   uint128 fundingFeePerBlock
  // ) internal view returns (SignedBalance memory) {
  //   if (fundingFee.lastUpdate > 0)
  //     fundingFee.balance = int256(fundingFee.balance)
  //       .add(
  //         uint256(fundingFeePerBlock).mulDown(
  //           int256(totalPositionM).sub(totalPositionT)
  //         ) * (block.number.sub(uint256(fundingFee.lastUpdate))).toInt256()
  //       )
  //       .toInt128();
  //   fundingFee.lastUpdate = block.number.toUint32();
  //   return fundingFee;
  // }

  function _getAccumulatedFee(
    bytes32 orderHash,
    bytes32 priceId,
    bool isBuy,
    uint128 leverage,
    uint128 margin
  )
    internal
    view
    returns (SignedBalance memory fundingFee, AccruedFee memory accruedFee)
  {
    // uint256 _totalPosition = isBuy
    //   ? totalLongPerPriceId[priceId]
    //   : totalShortPerPriceId[priceId];
    // fundingFee = isBuy
    //   ? _getLatestFundingFeeBalance(
    //     _longFundingFeePerPriceId[priceId],
    //     _totalPosition,
    //     totalShortPerPriceId[priceId],
    //     fundingFeePerPriceId[priceId]
    //   )
    //   : _getLatestFundingFeeBalance(
    //     _shortFundingFeePerPriceId[priceId],
    //     _totalPosition,
    //     totalLongPerPriceId[priceId],
    //     fundingFeePerPriceId[priceId]
    //   );

    // int256 accruedFundingFee = 0;
    // if (_totalPosition > 0) {
    //   accruedFundingFee = int256(fundingFee.balance)
    //     .mulDown(leverage)
    //     .mulDown(margin)
    //     .divDown(_totalPosition)
    //     .sub(_fundingFeeBaseByOrderHash[orderHash]);
    // }

    accruedFee = _accruedFeeByOrderHash[orderHash];
    // accruedFee.fundingFee = int256(accruedFee.fundingFee)
    //   .add(accruedFundingFee)
    //   .toInt128();
    accruedFee.fundingFee = 0;

    accruedFee.rolloverFee = uint256(accruedFee.rolloverFee)
      .add(
        uint256(rolloverFeePerPriceId[priceId]).mulDown(margin) *
          (block.number.sub(uint256(accruedFee.lastUpdate)))
      )
      .toUint128();
    accruedFee.lastUpdate = block.number.toUint32();
  }

  function _updateTrade(
    bytes32 orderHash,
    uint128 closePrice,
    uint128 margin,
    bool isAdd,
    uint256 liquidityBalance
  ) internal view returns (Trade memory trade) {
    trade = _openTradeByOrderHash(orderHash);

    uint256 position = uint256(trade.leverage).mulDown(trade.margin);
    (, AccruedFee memory accruedFee) = _getAccumulatedFee(
      orderHash,
      trade.priceId,
      trade.isBuy,
      trade.leverage,
      trade.margin
    );

    {
      if (isAdd) {
        _require(
          uint256(trade.margin).add(margin) <=
            position.divDown(minLeveragePerPriceId[trade.priceId]),
          Errors.INVALID_MARGIN
        );
        _require(
          uint256(totalMarginPerUser[trade.user]).add(margin) <
            maxMarginPerUser,
          Errors.MAX_MARGIN_PER_USER
        );
        _require(
          uint256(minCollateral).add(
            uint256(margin).mulDown(trade.maxPercentagePnL)
          ) <= liquidityBalance,
          Errors.MAX_LIQUIDITY_POOL
        );
        trade.margin = uint256(trade.margin).add(margin).toUint128();
      } else {
        _require(trade.margin > margin, Errors.INVALID_MARGIN);
        _require(
          uint256(trade.margin).sub(margin) >=
            position.divDown(maxLeveragePerPriceId[trade.priceId]),
          Errors.LEVERAGE_TOO_HIGH
        );
        trade.margin = uint256(trade.margin).sub(margin).toUint128();
      }
    }

    trade.leverage = position.divDown(trade.margin).toUint128();

    {
      int256 accumulatedFee = int256(accruedFee.fundingFee).add(
        uint256(accruedFee.rolloverFee)
      );

      if (trade.isBuy) {
        uint256 executionPrice = uint256(trade.openPrice).add(trade.slippage);
        int256 accumulatedFeePerPrice = executionPrice
          .mulDown(accumulatedFee)
          .divDown(position);
        trade.liquidationPrice = executionPrice
          .mulDown(
            uint256(trade.leverage)
              .sub(uint256(liquidationThresholdPerPriceId[trade.priceId]))
              .divDown(uint256(trade.leverage))
          )
          .toUint128();
        _require(
          closePrice >
            int256(uint256(trade.liquidationPrice).add(accumulatedFeePerPrice))
              .toUint256(),
          Errors.INVALID_MARGIN
        );
      } else {
        uint256 executionPrice = uint256(trade.openPrice).sub(trade.slippage);
        int256 accumulatedFeePerPrice = executionPrice
          .mulDown(accumulatedFee)
          .divDown(position);
        trade.liquidationPrice = executionPrice
          .mulDown(
            uint256(trade.leverage)
              .add(uint256(liquidationThresholdPerPriceId[trade.priceId]))
              .divDown(uint256(trade.leverage))
          )
          .toUint128();
        _require(
          closePrice <
            int256(uint256(trade.liquidationPrice).sub(accumulatedFeePerPrice))
              .toUint256(),
          Errors.INVALID_MARGIN
        );
      }
    }
  }

  function _updateStop(
    bytes32 orderHash,
    uint128 closePrice,
    uint128 profitTarget,
    uint128 stopLoss
  ) internal view returns (Trade memory trade) {
    trade = _openTradeByOrderHash(orderHash);

    uint256 closePosition = uint256(trade.leverage).mulDown(trade.margin);

    (, AccruedFee memory accruedFee) = _getAccumulatedFee(
      orderHash,
      trade.priceId,
      trade.isBuy,
      trade.leverage,
      trade.margin
    );

    int256 accumulatedFee = int256(accruedFee.fundingFee).add(
      accruedFee.rolloverFee
    );

    uint256 openNet = trade.isBuy
      ? uint256(trade.openPrice).add(trade.slippage)
      : uint256(trade.openPrice).sub(trade.slippage);

    uint256 closeNet = trade.isBuy
      ? int256(
        uint256(closePrice).sub(
          accumulatedFee.mulDown(openNet).divDown(closePosition)
        )
      ).toUint256()
      : int256(
        uint256(closePrice).add(
          accumulatedFee.mulDown(openNet).divDown(closePosition)
        )
      ).toUint256();

    _require(
      stopLoss == 0 ||
        (
          trade.isBuy
            ? uint256(stopLoss).add(minIncrement) < closeNet
            : uint256(stopLoss).sub(minIncrement) > closeNet
        ),
      Errors.INVALID_STOP_LOSS
    );
    _require(
      profitTarget == 0 ||
        (
          trade.isBuy
            ? uint256(profitTarget).sub(minIncrement) > closeNet
            : uint256(profitTarget).add(minIncrement) < closeNet
        ),
      Errors.INVALID_PROFIT_TARGET
    );

    trade.stopLoss = stopLoss;
    trade.profitTarget = profitTarget;
  }
}

