// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Position.sol";
import "./Order.sol";
import "./IDataStore.sol";
import "./IReader.sol";
import "./IManager.sol";
import "./IOrderCallbackReceiver.sol";
import "./IPerpetualVault.sol";
import "./IExchangeRouter.sol";
import "./IGmxUtils.sol";

/**
 * @title GMXUtils
 * @dev Contract for GMX Data Access
 */

contract GmxUtils is IOrderCallbackReceiver {
  using SafeERC20 for IERC20;
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
  bytes32 public constant SWAP_ORDER_GAS_LIMIT = keccak256(abi.encode("SWAP_ORDER_GAS_LIMIT"));
  bytes32 public constant SINGLE_SWAP_GAS_LIMIT = keccak256(abi.encode("SINGLE_SWAP_GAS_LIMIT"));
  
  bytes32 public constant IS_LONG = keccak256(abi.encode("IS_LONG"));
  
  bytes32 public constant referralCode = bytes32(0);
  uint256 public constant PRECISION = 1e30;
  uint256 public constant BASIS_POINTS_DIVISOR = 10_000;

  address public constant orderHandler = address(0x352f684ab9e97a6321a13CF03A61316B681D9fD2);
  IExchangeRouter public constant gExchangeRouter = IExchangeRouter(0x7C68C7866A64FA2160F78EEaE12217FFbf871fa8);
  IDataStore public constant dataStore = IDataStore(0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8);
  address public constant orderVault = address(0x31eF83a530Fde1B38EE9A18093A333D8Bbbc40D5);
  IReader public constant reader = IReader(0xf60becbba223EEA9495Da3f606753867eC10d139);
  address public constant referralStorage = address(0xe6fab3F0c7199b0d34d7FbE83394fc0e0D06e99d);
  
  address public perpVault;
  IManager public manager;

  modifier onlyOwner() {
    require(perpVault == address(0) || msg.sender == perpVault, "!owner");
    _;
  }

  receive() external payable {}

  function getPositionInfo(
    bytes32 key,
    MarketPrices memory prices
  ) public view returns (PositionData memory) {
    PositionInfo memory positionInfo = reader.getPositionInfo(
      address(dataStore),
      referralStorage,
      key,
      prices,
      uint256(0),
      address(0),
      true
    );
    uint256 netValueInCollateralToken;    // need to consider positive funding fee. it's claimable amount
    if (positionInfo.pnlAfterPriceImpactUsd >= 0) {
      netValueInCollateralToken = positionInfo.position.numbers.collateralAmount + 
        uint256(positionInfo.pnlAfterPriceImpactUsd) / prices.shortTokenPrice.max
        - positionInfo.fees.borrowing.borrowingFeeUsd / prices.shortTokenPrice.max
        - positionInfo.fees.funding.fundingFeeAmount
        - positionInfo.fees.positionFeeAmount;
    } else {
      netValueInCollateralToken = positionInfo.position.numbers.collateralAmount - 
        (uint256(-positionInfo.pnlAfterPriceImpactUsd) + positionInfo.fees.borrowing.borrowingFeeUsd) / prices.shortTokenPrice.max
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

  function getPositionSizeInUsd(bytes32 key) external view returns (uint256 sizeInUsd) {
    sizeInUsd = dataStore.getUint(keccak256(abi.encode(key, SIZE_IN_USD)));
  }

  function getExecutionGasLimit(Order.OrderType orderType, uint256 _callbackGasLimit) internal view returns (uint256 executionGasLimit) {
    uint256 baseGasLimit = dataStore.getUint(ESTIMATED_GAS_FEE_BASE_AMOUNT);
    uint256 multiplierFactor = dataStore.getUint(ESTIMATED_GAS_FEE_MULTIPLIER_FACTOR);
    uint256 gasPerSwap = dataStore.getUint(SINGLE_SWAP_GAS_LIMIT);
    uint256 estimatedGasLimit;
    if (orderType == Order.OrderType.MarketIncrease) {
      estimatedGasLimit = dataStore.getUint(INCREASE_ORDER_GAS_LIMIT) + gasPerSwap;
    } else if (orderType == Order.OrderType.MarketDecrease) {
      estimatedGasLimit = dataStore.getUint(DECREASE_ORDER_GAS_LIMIT) + gasPerSwap;
    } else if (orderType == Order.OrderType.LimitDecrease) {
      estimatedGasLimit = dataStore.getUint(DECREASE_ORDER_GAS_LIMIT) + gasPerSwap;
    } else if (orderType == Order.OrderType.StopLossDecrease) {
      estimatedGasLimit = dataStore.getUint(DECREASE_ORDER_GAS_LIMIT) + gasPerSwap;
    } else if (orderType == Order.OrderType.MarketSwap) {
      estimatedGasLimit = dataStore.getUint(SWAP_ORDER_GAS_LIMIT) + gasPerSwap;
    }
    // multiply 1.2 (add some buffer) to ensure that the creation transaction does not revert.
    executionGasLimit = baseGasLimit + (estimatedGasLimit + _callbackGasLimit) * multiplierFactor / PRECISION;
  }

  function tokenToUsdMin(address token, uint256 balance) external view returns (uint256) {
    return manager.getTokenPrice(token) * balance;
  }

  function usdToTokenAmount(address token, uint256 usd) external view returns (uint256) {
    return usd / manager.getTokenPrice(token);
  }

  function afterOrderExecution(bytes32 key, Order.Props memory order, EventLogData memory /* eventData */) external override {
    require(msg.sender == address(orderHandler), "invalid caller");
    bytes32 positionKey = keccak256(abi.encode(address(this), order.addresses.market, order.addresses.initialCollateralToken, order.flags.isLong));
    IPerpetualVault(perpVault).afterOrderExecution(key, order.numbers.orderType, order.flags.isLong, positionKey);
  }

  function afterOrderCancellation(bytes32 key, Order.Props memory order, EventLogData memory /* eventData */) external override {
    require(msg.sender == address(orderHandler), "invalid caller");
    IPerpetualVault(perpVault).afterOrderCancellation(key, order.numbers.orderType, order.flags.isLong, bytes32(0));
  }

  function afterOrderFrozen(bytes32 key, Order.Props memory order, EventLogData memory /* eventData */) external override {}

  function setEnvVars(address _perpVault, address _manager) external onlyOwner {
    perpVault = _perpVault;
    manager = IManager(_manager);
  }

  function createOrder(
    Order.OrderType orderType,
    IGmxUtils.OrderData memory orderData,
    MarketPrices memory prices
  ) external returns (bytes32) {
    uint256 positionExecutionFee = getExecutionGasLimit(orderType, orderData.callbackGasLimit) * tx.gasprice;
    require(address(this).balance >= positionExecutionFee, "insufficient eth balance");
    gExchangeRouter.sendWnt{value: positionExecutionFee}(orderVault, positionExecutionFee);
    if (
      orderType == Order.OrderType.MarketSwap ||
      orderType == Order.OrderType.MarketIncrease
    ) {
      IERC20(orderData.initialCollateralToken).safeApprove(address(0x7452c558d45f8afC8c83dAe62C3f8A5BE19c71f6), orderData.amountIn);
      gExchangeRouter.sendTokens(orderData.initialCollateralToken, orderVault, orderData.amountIn);
    }
    CreateOrderParamsAddresses memory paramsAddresses = CreateOrderParamsAddresses({
      receiver: address(this),
      callbackContract: address(this),
      uiFeeReceiver: address(0),
      market: orderData.market,
      initialCollateralToken: orderData.initialCollateralToken,
      swapPath: orderData.swapPath
    });
    uint256 acceptablePrice;
    if (orderType != Order.OrderType.MarketSwap) {
      if (orderData.isLong) {
        acceptablePrice = prices.indexTokenPrice.min * (BASIS_POINTS_DIVISOR - 30) / BASIS_POINTS_DIVISOR;   // apply 0.3% offset
      } else {
        acceptablePrice = prices.indexTokenPrice.max * (BASIS_POINTS_DIVISOR + 30) / BASIS_POINTS_DIVISOR;   // apply 0.3% offset
      }
    }

    CreateOrderParamsNumbers memory paramsNumber = CreateOrderParamsNumbers({
      sizeDeltaUsd: orderData.sizeDeltaUsd,
      initialCollateralDeltaAmount: orderData.initialCollateralDeltaAmount,
      triggerPrice: 0,      // this param is an opening trigger price. not closing trigger price
      acceptablePrice: acceptablePrice,
      executionFee: positionExecutionFee,
      callbackGasLimit: orderData.callbackGasLimit,
      minOutputAmount: 0      // this param is used when swapping. is not used in opening position even though swap involved.
    });
    CreateOrderParams memory params = CreateOrderParams({
      addresses: paramsAddresses,
      numbers: paramsNumber,
      orderType: orderType,
      decreasePositionSwapType: Order.DecreasePositionSwapType.SwapPnlTokenToCollateralToken,
      isLong: orderData.isLong,
      shouldUnwrapNativeToken: false,
      referralCode: referralCode
    });
    bytes32 requestKey = gExchangeRouter.createOrder(params);
    return requestKey;
  }

  function createDecreaseOrder(
    bytes32 key,
    address market,
    bool isLong,
    uint256 sl,
    uint256 tp,
    uint256 callbackGasLimit,
    MarketPrices memory prices
  ) external {
    MarketProps memory marketInfo = reader.getMarket(address(dataStore), market);
    PositionData memory positionData = getPositionInfo(key, prices);

    uint256 acceptablePrice = isLong ?
      prices.indexTokenPrice.min * (BASIS_POINTS_DIVISOR - 30) / BASIS_POINTS_DIVISOR :
      prices.indexTokenPrice.max * (BASIS_POINTS_DIVISOR + 30) / BASIS_POINTS_DIVISOR;
    
    address[] memory swapPath;
    CreateOrderParamsAddresses memory paramsAddresses = CreateOrderParamsAddresses({
      receiver: address(this),
      callbackContract: address(this),
      uiFeeReceiver: address(0),
      market: market,
      initialCollateralToken: marketInfo.shortToken,
      swapPath: swapPath
    });
    uint256 positionExecutionFee = getExecutionGasLimit(Order.OrderType.LimitDecrease, callbackGasLimit) * tx.gasprice;
    require(address(this).balance >= positionExecutionFee, "too low execution fee");
    gExchangeRouter.sendWnt{value: positionExecutionFee}(orderVault, positionExecutionFee);
    CreateOrderParamsNumbers memory paramsNumber = CreateOrderParamsNumbers({
      sizeDeltaUsd: positionData.sizeInUsd,
      initialCollateralDeltaAmount: positionData.collateralAmount,
      triggerPrice: tp,      // this param is an opening trigger price. not closing trigger price
      acceptablePrice: acceptablePrice,
      executionFee: positionExecutionFee,
      callbackGasLimit: callbackGasLimit,
      minOutputAmount: 0      // this param is used when swapping. is not used in opening position even though swap involved.
    });
    CreateOrderParams memory params = CreateOrderParams({
      addresses: paramsAddresses,
      numbers: paramsNumber,
      orderType: Order.OrderType.LimitDecrease,
      decreasePositionSwapType: Order.DecreasePositionSwapType.NoSwap,
      isLong: isLong,
      shouldUnwrapNativeToken: false,
      referralCode: referralCode
    });
    gExchangeRouter.createOrder(params);

    positionExecutionFee = getExecutionGasLimit(Order.OrderType.StopLossDecrease, callbackGasLimit) * tx.gasprice;
    require(address(this).balance >= positionExecutionFee, "too low execution fee");
    gExchangeRouter.sendWnt{value: positionExecutionFee}(orderVault, positionExecutionFee);
    paramsNumber = CreateOrderParamsNumbers({
      sizeDeltaUsd: positionData.sizeInUsd,
      initialCollateralDeltaAmount: positionData.collateralAmount,
      triggerPrice: sl,      // this param is an opening trigger price. not closing trigger price
      acceptablePrice: acceptablePrice,
      executionFee: positionExecutionFee,
      callbackGasLimit: callbackGasLimit,
      minOutputAmount: 0      // this param is used when swapping. is not used in opening position even though swap involved.
    });

    params = CreateOrderParams({
      addresses: paramsAddresses,
      numbers: paramsNumber,
      orderType: Order.OrderType.StopLossDecrease,
      decreasePositionSwapType: Order.DecreasePositionSwapType.NoSwap,
      isLong: isLong,
      shouldUnwrapNativeToken: false,
      referralCode: referralCode
    });
    gExchangeRouter.createOrder(params);
  }

  function withdrawEth() external onlyOwner returns (uint256) {
    uint256 balance = address(this).balance;
    payable(msg.sender).transfer(balance);
    return balance;
  }
}

