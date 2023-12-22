// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "./Position.sol";
import "./Order.sol";
import "./IDataStore.sol";
import "./IReader.sol";
import "./IManager.sol";
import "./IOrderCallbackReceiver.sol";
import "./IPerpetualVault.sol";

import "./console.sol";

/**
 * @title GMXUtils
 * @dev Contract for GMX Data Access
 */

contract GmxUtils is IOrderCallbackReceiver {
  using Position for Position.Props;

  struct PositionData {
    uint256 sizeInUsd;
    uint256 sizeInTokens;
    uint256 collateralAmount;
    uint256 netValueInCollateralToken;
    bool isLong;
  }

  bytes32 public constant COLLATERAL_TOKEN = keccak256(abi.encode("COLLATERAL_TOKEN"));

  bytes32 public constant SIZE_IN_USD = keccak256(abi.encode("SIZE_IN_USD"));
  bytes32 public constant SIZE_IN_TOKENS = keccak256(abi.encode("SIZE_IN_TOKENS"));
  bytes32 public constant COLLATERAL_AMOUNT = keccak256(abi.encode("COLLATERAL_AMOUNT"));
  bytes32 public constant ESTIMATED_GAS_FEE_BASE_AMOUNT = keccak256(abi.encode("ESTIMATED_GAS_FEE_BASE_AMOUNT"));
  bytes32 public constant ESTIMATED_GAS_FEE_MULTIPLIER_FACTOR = keccak256(abi.encode("ESTIMATED_GAS_FEE_MULTIPLIER_FACTOR"));
  bytes32 public constant INCREASE_ORDER_GAS_LIMIT = keccak256(abi.encode("INCREASE_ORDER_GAS_LIMIT"));
  bytes32 public constant DECREASE_ORDER_GAS_LIMIT = keccak256(abi.encode("DECREASE_ORDER_GAS_LIMIT"));
  
  bytes32 public constant IS_LONG = keccak256(abi.encode("IS_LONG"));

  uint256 public constant PRECISION = 1e30;

  address public perpVault;
  address public orderHandler = address(0x352f684ab9e97a6321a13CF03A61316B681D9fD2);

  modifier onlyOwner() {
    require(perpVault == address(0) || msg.sender == perpVault, "!owner");
    _;
  }

  // function getPositionInfo(
  //   // IDataStore dataStore,
  //   // bytes32 key
  // ) external view returns (PositionInfo memory) {
  //   // if (key == bytes32(0)) {
  //   //   return (address(0), 0, 0, 0, false);
  //   // }

  //   // address collateralToken = dataStore.getAddress(keccak256(abi.encode(key, COLLATERAL_TOKEN)));
  //   // uint256 sizeInUsd = dataStore.getUint(keccak256(abi.encode(key, SIZE_IN_USD)));
  //   // uint256 sizeInToken = dataStore.getUint(keccak256(abi.encode(key, SIZE_IN_TOKENS)));
  //   // uint256 collateralAmount = dataStore.getUint(keccak256(abi.encode(key, COLLATERAL_AMOUNT)));
  //   // bool isLong = dataStore.getBool(keccak256(abi.encode(key, IS_LONG)));

  //   // return (collateralToken, sizeInUsd, sizeInToken, collateralAmount, isLong);

  //   MarketPrices memory price = MarketPrices({
  //     indexTokenPrice: PriceProps({min: 1788509312150000, max: 1788754347820000}),
  //     longTokenPrice: PriceProps({min: 1788509312150000, max: 1788754347820000}),
  //     shortTokenPrice: PriceProps({min: 999902030000000000000000, max: 1000011850000000000000000})
  //   });
  //   PositionInfo memory positionInfo = IReader(0xf60becbba223EEA9495Da3f606753867eC10d139).getPositionInfo(
  //     address(0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8),
  //     address(0xe6fab3F0c7199b0d34d7FbE83394fc0e0D06e99d),
  //     bytes32(0x92377b80d2771a46f0a8ee4204bdd278b96be2bbadc0e1604d059b46ce7cfd21),    // short - bytes32(0x216e5c3dd561a82227902b49888fab1d30e6ab6a62bd3b594476c3ea1f840cdc)
  //     price,
  //     10990430847000000000000000000000,
  //     address(0),
  //     true
  //   );
  //   console.log(positionInfo.fees.borrowing.borrowingFeeUsd);
  //   return positionInfo;
  // }

  function getPositionInfo(
    address dataStore,
    IReader reader,
    address market,
    address referralStorage,
    bytes32 key,
    IManager manager
  ) external view returns (PositionData memory) {
    MarketProps memory marketInfo = reader.getMarket(dataStore, market);
    uint256 indexTokenPrice = manager.getTokenPrice(marketInfo.indexToken);
    uint256 longTokenPrice = manager.getTokenPrice(marketInfo.longToken);
    uint256 shortTokenPrice = manager.getTokenPrice(marketInfo.shortToken);
    MarketPrices memory prices = MarketPrices({
      indexTokenPrice: PriceProps({min: indexTokenPrice, max: indexTokenPrice}),
      longTokenPrice: PriceProps({min: longTokenPrice, max: longTokenPrice}),
      shortTokenPrice: PriceProps({min: shortTokenPrice, max: shortTokenPrice})
    });
    PositionInfo memory positionInfo = reader.getPositionInfo(
      dataStore,
      referralStorage,
      key,
      prices,
      uint256(0),
      address(0),
      true
    );
    uint256 netValueInCollateralToken;
    if (positionInfo.pnlAfterPriceImpactUsd >= 0) {
      netValueInCollateralToken = positionInfo.position.numbers.collateralAmount + 
        uint256(positionInfo.pnlAfterPriceImpactUsd) / shortTokenPrice
        - positionInfo.fees.borrowing.borrowingFeeUsd / shortTokenPrice
        - positionInfo.fees.funding.fundingFeeAmount
        - positionInfo.fees.positionFeeAmount;
    } else {
      netValueInCollateralToken = positionInfo.position.numbers.collateralAmount - 
        (uint256(positionInfo.pnlAfterPriceImpactUsd) + positionInfo.fees.borrowing.borrowingFeeUsd) / shortTokenPrice
        - positionInfo.fees.funding.fundingFeeAmount
        - positionInfo.fees.positionFeeAmount;
    }

    return PositionData({
      sizeInUsd: positionInfo.position.numbers.sizeInUsd,
      sizeInTokens: positionInfo.position.numbers.sizeInTokens,
      collateralAmount: positionInfo.position.numbers.collateralAmount,
      netValueInCollateralToken: netValueInCollateralToken,
      isLong: positionInfo.position.flags.isLong
    });
  }

  function getPositionSizeInUsd(IDataStore dataStore, bytes32 key) external view returns (uint256 sizeInUsd) {
    sizeInUsd = dataStore.getUint(keccak256(abi.encode(key, SIZE_IN_USD)));
  }

  function getExecutionGasLimit(IDataStore dataStore, Order.OrderType orderType, uint256 _callbackGasLimit) external view returns (uint256 executionGasLimit) {
    uint256 baseGasLimit = dataStore.getUint(ESTIMATED_GAS_FEE_BASE_AMOUNT);
    console.log('baseGasLimit:', baseGasLimit);
    uint256 multiplierFactor = dataStore.getUint(ESTIMATED_GAS_FEE_MULTIPLIER_FACTOR);
    console.log('multiplierFactor:', multiplierFactor);
    uint256 estimatedGasLimit;
    if (orderType == Order.OrderType.MarketIncrease) {
      estimatedGasLimit = dataStore.getUint(INCREASE_ORDER_GAS_LIMIT);
      console.log('estimatedGasLimit:', estimatedGasLimit);
    } else if (orderType == Order.OrderType.MarketDecrease) {
      estimatedGasLimit = dataStore.getUint(DECREASE_ORDER_GAS_LIMIT);
    } else if (orderType == Order.OrderType.LimitDecrease) {
      estimatedGasLimit = dataStore.getUint(DECREASE_ORDER_GAS_LIMIT);
    } else if (orderType == Order.OrderType.StopLossDecrease) {
      estimatedGasLimit = dataStore.getUint(DECREASE_ORDER_GAS_LIMIT);
    }
    // multiply 1.2 (add some buffer) to ensure that the creation transaction does not revert.
    executionGasLimit = baseGasLimit + (estimatedGasLimit + _callbackGasLimit) * multiplierFactor / PRECISION;
  }

  function tokenToUsdMin(IManager manager, address token, uint256 balance) external view returns (uint256) {
    return manager.getTokenPrice(token) * balance;
  }

  function afterOrderExecution(bytes32 key, Order.Props memory order, EventLogData memory /* eventData */) external override {
    require(msg.sender == address(orderHandler), "invalid caller");
    IPerpetualVault(perpVault).afterOrderExecution(key, order);
  }

  function afterOrderCancellation(bytes32 key, Order.Props memory order, EventLogData memory /* eventData */) external override {
    require(msg.sender == address(orderHandler), "invalid caller");
    IPerpetualVault(perpVault).afterOrderCancellation(key, order);
  }

  function afterOrderFrozen(bytes32 key, Order.Props memory order, EventLogData memory /* eventData */) external override {}

  function setPerpVault(address _perpVault) external onlyOwner {
    perpVault = _perpVault;
  }
}

