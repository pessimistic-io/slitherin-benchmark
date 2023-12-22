// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.18;

import "./OwnableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./SafeERC20.sol";

import {IOrderHandler, MarketUtils, Price, Market, IReferralStorage, IMarketToken, ISwapHandler, IOrderVault, IGMXOracle, IEventEmitter, BaseOrderUtils, PositionUtils, IGMXUtils, Order, IOrderUtils, IDataStore, IReader, IExchangeRouter, Position, EventUtils, IOrderCallbackReceiver} from "./IGMX.sol";

import "./IGMXHedger.sol";
import "./IHedgedPool.sol";

import "./IERC20.sol";

import {IOracle} from "./IGamma.sol";

import "./console.sol";

/// @title Perennial protocol perpetual hedger
/// @notice Hedges pool delta by trading perpetual contracts

//Hedger should be owner of positions hedgedPool is where collateral is

contract GMXHedger is IGMXHedger, OwnableUpgradeable, IOrderCallbackReceiver {
    using SafeERC20 for IERC20;
    using Price for Price.Props;
    using Position for Position.Props;

    event HedgeUpdated(int256 oldDelta, int256 newDelta);

    event Synced(int256 collateralDiff);

    // Gmx uses 30 decimals precision
    uint256 private constant GMX_DECIMALS = 30;

    uint256 private constant SIREN_DECIMALS = 8;

    uint256 private constant ORDER_GAS_LIMIT = 7e6;

    uint256 private constant ACCEPTABLE_PRICE_THRESHOLD = 10;

    // Siren HedgedPool that will be our account for this contract
    address public hedgedPool;

    //ExchangeRouter what we use to execute orders
    address public exchangeRouter;

    address public orderVault;

    address public dataStore;

    address public reader;

    //Market that our long token is based on ie weth, wbtc, ect
    address public market;

    uint256 public leverage;

    IERC20 collateralToken;

    uint256 public collateralDecimals;

    address public gmxUtils;

    uint256 public underlyingDecimals;

    int256 private deltaCached;

    Market.Props public marketProps;

    bytes32[] public keys;

    //TODO:
    // IOrderCallback recieve this will recieve the call back from afterOrderExecution recieve key, order, eventData
    // Need to check that the message sender is orderHandler
    // store key instead of counter

    //TODO: Mock Hedger pool
    // return IERC20(collateral) token
    // return getcollateralbalance() balance of collateral token
    // in constructor pass the address of the hedger, collateral token,
    // give infi approval to hedger for collateral

    BaseOrderUtils.ExecuteOrderParamsContracts executOrderParamContracts;

    modifier onlyPool() {
        // if(msg.sender != hedgedPool) {
        //     if(!IHedgedPool(hedgedPool).keepers(msg.sender)) {
        //         revert("only pool or keeper");
        //     }
        // }
        _;
    }

    modifier keyCountTooHigh() {
        require(keys.length < 2, "key count too high");
        _;
    }

    function __GMX_Hedger_init(
        address _hedgedPool,
        address _exchangeRouter,
        address _reader,
        address _market,
        address _gmxUtils,
        uint256 _leverage
    ) external initializer {
        market = _market;
        _updateConfig(_exchangeRouter, _reader, _gmxUtils, _leverage);
    
        underlyingDecimals = IMarketToken(market).decimals();

        hedgedPool = _hedgedPool;
        collateralToken = IHedgedPool(hedgedPool).collateralToken();
        collateralDecimals = IERC20MetadataUpgradeable(address(collateralToken))
            .decimals();

        __Ownable_init();
    }

    // /// @notice Update hedger configuration
    function updateConfig(
        address _exchangeRouter,
        address _reader,
        address _gmxUtils,
        uint256 _leverage
    ) external onlyOwner {
        _updateConfig(_exchangeRouter, _reader, _gmxUtils, _leverage);
    }

    function _updateConfig(
        address _exchangeRouter,
        address _reader,
        address _gmxUtils,
        uint256 _leverage
    ) private {
        leverage = _leverage;
        reader = _reader;
        exchangeRouter = _exchangeRouter;
        IOrderHandler orderHandler = IOrderHandler(
            IExchangeRouter(_exchangeRouter).orderHandler()
        );
        dataStore = address(IExchangeRouter(exchangeRouter).dataStore());

        (address marketToken, address indexToken, address longToken, address shortToken) = IReader(reader).getMarket(dataStore, market);

        marketProps = Market.Props(marketToken, indexToken, longToken, shortToken);

        orderVault = address(orderHandler.orderVault());
        IGMXOracle gmxOralce = orderHandler.oracle();
        ISwapHandler swapHandler = orderHandler.swapHandler();
        IReferralStorage referralStorage = orderHandler.referralStorage();
        gmxUtils = _gmxUtils;

        executOrderParamContracts = BaseOrderUtils.ExecuteOrderParamsContracts(
            IDataStore(dataStore),
            IEventEmitter(IExchangeRouter(exchangeRouter).eventEmitter()),
            IOrderVault(orderVault),
            gmxOralce,
            swapHandler,
            referralStorage
        );
    }

    function afterOrderExecution(
        bytes32 key,
        Order.Props memory order,
        EventUtils.EventLogData memory eventData
    ) external {
        require(
            address(msg.sender) ==
                address(IExchangeRouter(exchangeRouter).orderHandler())
        );
        uint256 keysLength = keys.length;
        for (uint256 i = 0; i < keysLength; i++) {
            if (keys[i] == key) {
                keys[i] = keys[i + 1];
            }
        }
        keys.pop();
    }

    // /// @notice Set maintenance buffer in percent (200 means 2x maintenance required by product)
    // function setMaintenanceBuffer(
    //     uint256 _maintenanceBuffer
    // ) external onlyOwner {
    //     maintenanceBuffer = _maintenanceBuffer;
    // }

    /// @notice Adjust perpetual position in order to hedge given delta exposure
    /// @param targetDelta Target delta of the hedge (1e8)
    /// @param prices minPrice from GMX oracle multiplied by oracle decimals
    /// @return deltaDiff difference between the new delta and the old delta
    function hedge(
        int256 targetDelta,
        MarketUtils.MarketPrices calldata prices
    ) external onlyPool returns (int256 deltaDiff) {
        _syncDelta();

        // calculate changes in long and short
        uint currentLong;
        uint currentShort;
        uint targetLong;
        uint targetShort;

        if (targetDelta >= 0) {
            targetLong = uint256(targetDelta);

            // need long hedge
            if (deltaCached >= 0) {
                currentLong = uint256(deltaCached);
            } else {
                currentShort = uint256(-deltaCached);
            }
        } else if (targetDelta < 0) {
            targetShort = uint256(-targetDelta);

            // need short hedge
            if (deltaCached <= 0) {
                currentShort = uint256(-deltaCached);
            } else {
                currentLong = uint256(deltaCached);
            }
        }

        _changePosition(
            currentLong,
            targetLong,
            currentShort,
            targetShort,
            prices
        );

        emit HedgeUpdated(deltaCached, targetDelta);

        deltaCached = targetDelta;

        return deltaDiff;
    }

    function sync() external onlyPool returns (int256 collateralDiff) {
        _sync();
    }

    function getDelta() external view returns (int256) {
        return deltaCached;
    }

    function getCollateralValue() external returns (uint256) {
        MarketUtils.MarketPrices memory prices = _getMarketPrices();
        uint256 collateralValue;

        (
            Position.Props memory longPosition,
            Position.Props memory shortPosition
        ) = _getPositionInformation();

        bool isLong = true;
        while (true) {
            Position.Props memory position = isLong
                ? longPosition
                : shortPosition;

            // TODO: handle edge case where position value is below zero
            collateralValue += uint256(
                int256(position.collateralAmount()) +
                    _getPositinPnlCollateral(isLong, prices)
            );

            if (isLong) {
                isLong = false;
            } else {
                break;
            }
        }

        return collateralValue;
    }

    /// @notice Get required collateral
    /// @return collateral shortfall (positive) or excess (negative)
    function getRequiredCollateral() external returns (int256) {
        int256 requiredCollateral;

        MarketUtils.MarketPrices memory prices = _getMarketPrices();
        uint256 indexTokenPrice = prices.indexTokenPrice.min;

        (
            Position.Props memory longPosition,
            Position.Props memory shortPosition
        ) = _getPositionInformation();

        bool isLong = true;
        while (true) {
            Position.Props memory position = isLong
                ? longPosition
                : shortPosition;

            int256 marginCurrent = int256(position.collateralAmount()) +
                _getPositinPnlCollateral(isLong, prices);
            uint256 marginRequired = _getMarginRequired(
                position.sizeInTokens(),
                indexTokenPrice
            );

            requiredCollateral += int256(marginRequired) - marginCurrent;

            if (isLong) {
                isLong = false;
            } else {
                break;
            }
        }

        return requiredCollateral;
    }

    /// @notice Withdraw excess collateral or deposit more
    /// @return collateralDiff deposit (positive) or withdrawal (negative) amount
    function _sync() internal returns (int collateralDiff) {
        (
            Position.Props memory longPosition,
            Position.Props memory shortPosition
        ) = _getPositionInformation();

        bool isLong = true;
        MarketUtils.MarketPrices memory prices = _getMarketPrices();
        uint256 indexTokenPrice = prices.indexTokenPrice.min;

        while (true) {
            Position.Props memory position = isLong
                ? longPosition
                : shortPosition;

            int256 marginCurrent = int256(position.collateralAmount()) +
                _getPositinPnlCollateral(isLong, prices);
            uint256 marginRequired = _getMarginRequired(
                position.sizeInTokens(),
                indexTokenPrice
            );

            if (int256(marginRequired) > marginCurrent) {
                uint256 acceptablePrice = _getAcceptablePrice(
                    indexTokenPrice,
                    true,
                    isLong
                );

                // deposit
                _depositCollateral(
                    isLong,
                    uint256(int256(marginRequired) - marginCurrent),
                    acceptablePrice
                );
            } else if (int256(marginRequired) < marginCurrent) {
                uint256 acceptablePrice = _getAcceptablePrice(
                    indexTokenPrice,
                    false,
                    isLong
                );

                // withdraw
                _withdrawCollateral(
                    isLong,
                    uint256(marginCurrent) - marginRequired,
                    acceptablePrice
                );
            }

            if (isLong) {
                isLong = false;
            } else {
                break;
            }
        }
    }

    /// @notice sync cached delta value
    function _syncDelta() internal {
        int256 totalSizeInTokens;

        (
            Position.Props memory longPosition,
            Position.Props memory shortPosition
        ) = _getPositionInformation();

        bool isLong = true;
        // TODO: think of edge case during pending orders
        while (true) {
            Position.Props memory position = isLong
                ? longPosition
                : shortPosition;

            uint256 sizeInTokens = position.sizeInTokens();
            require(
                sizeInTokens == 0 || totalSizeInTokens == 0,
                "two non-zero positions"
            );

            totalSizeInTokens += isLong
                ? int256(sizeInTokens)
                : -int256(sizeInTokens);

            if (isLong) {
                isLong = false;
            } else {
                break;
            }
        }

        deltaCached =
            (totalSizeInTokens * int256(10 ** SIREN_DECIMALS)) /
            int256(10 ** underlyingDecimals);
    }

    function _getPositionInformation()
        internal
        view
        returns (
            Position.Props memory longPosition,
            Position.Props memory shortPosition
        )
    {
        //TODO update this so the hedger doesnt have to loop
        Position.Props[] memory allPositions = IReader(reader)
            .getAccountPositions(IDataStore(dataStore), address(this), 0, 2);
        for (uint256 i; i < allPositions.length; i++) {
            if (allPositions[i].flags.isLong == true) {
                longPosition = allPositions[i];
            } else {
                shortPosition = allPositions[i];
            }
        }

        return (longPosition, shortPosition);
    }

    function _getPositinPnlCollateral(
        bool isLong,
        MarketUtils.MarketPrices memory prices
    ) internal returns (int256) {
        bytes32 key = _getPositionKey(address(msg.sender), isLong);

        (int256 positionPnlUsd, , ) = IReader(reader).getPositionPnlUsd(
            IDataStore(dataStore),
            marketProps,
            prices,
            key,
            0
        );

        // convert to collateral
        positionPnlUsd =
            positionPnlUsd /
            int256((10 ** (GMX_DECIMALS - collateralDecimals)));

        return (positionPnlUsd);
    }

    //Internal Helper Functions

    //Do we need this or can we just set this in the init function
    function _createOrderParamAddresses()
        internal
        returns (IOrderUtils.CreateOrderParamsAddresses memory)
    {
        //SwapPath for this I think should always be usdc->collateralToken if thats the case we can set this in init
        address[] memory swapPath;
        return
            IOrderUtils.CreateOrderParamsAddresses(
                address(hedgedPool),
                address(this),
                address(this),
                market,
                address(collateralToken),
                swapPath
            );
    }

    function _orderParamAddresses() internal returns (Order.Addresses memory) {
        address[] memory swapPath;
        return
            Order.Addresses(
                address(this),
                address(this),
                address(this),
                address(this),
                market,
                address(collateralToken),
                swapPath
            );
    }

    function _createOrderParamNumbers(
        uint256 sizeDeltaUSD,
        uint256 initialCollateralDeltaAmount,
        uint256 minOutputAmount,
        uint256 acceptablePrice
    ) internal returns (IOrderUtils.CreateOrderParamsNumbers memory) {
        //WE need a way to get this price
        //Fetch Acceptable price from somwwhere
        uint256 executionFee = 715000000000000;

        return
            IOrderUtils.CreateOrderParamsNumbers(
                sizeDeltaUSD,
                initialCollateralDeltaAmount,
                0,
                acceptablePrice,
                executionFee,
                0,
                minOutputAmount
            );
    }

    function _orderParamNumbers(
        uint256 sizeDeltaUSD,
        uint256 initialCollateralDeltaAmount,
        uint256 minOutputAmount,
        uint256 acceptablePrice,
        Order.OrderType orderType
    ) internal returns (Order.Numbers memory) {
        //WE need a way to get this price
        //Fetch Acceptable price from somwwhere
        uint256 executionFee = 715000000000000;

        return
            Order.Numbers(
                orderType,
                Order.DecreasePositionSwapType.NoSwap,
                sizeDeltaUSD,
                initialCollateralDeltaAmount,
                0,
                acceptablePrice,
                executionFee,
                0,
                minOutputAmount,
                block.number
            );
    }

    function _getOrderType() internal returns (Order.OrderType) {}

    function _createMarketOrder(
        IOrderUtils.CreateOrderParamsAddresses memory createOrderParamAddresses,
        IOrderUtils.CreateOrderParamsNumbers memory createOrderParamNumbers,
        Order.OrderType orderType,
        Order.DecreasePositionSwapType decreasePositionSwap,
        bool isLong,
        bool shouldUnwrapNativeToken,
        bytes32 referralCode
    ) internal returns (bytes32) {
        bytes32 key = IExchangeRouter(exchangeRouter).createOrder(
            IOrderUtils.CreateOrderParams(
                createOrderParamAddresses,
                createOrderParamNumbers,
                orderType,
                decreasePositionSwap,
                isLong,
                shouldUnwrapNativeToken,
                referralCode
            )
        );
        console.log("Key");
        console.logBytes32(key);
        return (key);
    }

    function _sendTokens(
        address collateralAddress,
        uint256 collateralAmount
    ) internal {
        IERC20(collateralAddress).approve(
            IExchangeRouter(exchangeRouter).router(),
            collateralAmount
        );
        IExchangeRouter(exchangeRouter).sendTokens(
            collateralAddress,
            orderVault,
            collateralAmount
        );
    }

    //TODO
    // 1. Add price for change position possibly 2 prices
    //
    function _changePosition(
        uint256 currentLong,
        uint256 targetLong,
        uint256 currentShort,
        uint256 targetShort,
        MarketUtils.MarketPrices calldata prices
    ) internal {
        (
            Position.Props memory longPosition,
            Position.Props memory shortPosition
        ) = _getPositionInformation();

        bool isLong = true;
        while (true) {
            uint256 currentPos = isLong ? currentLong : currentShort;
            uint256 targetPos = isLong ? targetLong : targetShort;

            if (targetPos == currentPos) continue;

            uint256 price = prices.indexTokenPrice.pickPrice(isLong);

            uint256 acceptablePrice = _getAcceptablePrice(
                price,
                targetPos > currentPos,
                isLong
            );

            Position.Props memory position = isLong
                ? longPosition
                : shortPosition;

            int256 marginCurrent = int256(position.collateralAmount()) +
                _getPositinPnlCollateral(isLong, prices);
            uint256 marginRequired = _getMarginRequired(
                (targetPos * (10 ** underlyingDecimals)) /
                    (10 ** SIREN_DECIMALS),
                price
            );

            if (targetPos > currentPos) {
                // increase position

                //First get the sizeInTokens of the position
                uint256 initialCollateralDelta;
                if (marginRequired > uint256(marginCurrent)) {
                    initialCollateralDelta = uint256(
                        marginRequired - uint256(marginCurrent)
                    );

                    collateralToken.safeTransferFrom(
                        hedgedPool,
                        address(this),
                        initialCollateralDelta
                    );
                }

                uint256 sizeDeltaUsd = ((targetPos - currentPos) *
                    price *
                    (10 ** underlyingDecimals)) / (10 ** SIREN_DECIMALS);

                //Adjust for slippage
                uint256 executionPrice = _calculateAdjustedExecutionPrice(
                    position,
                    prices,
                    isLong,
                    sizeDeltaUsd,
                    initialCollateralDelta,
                    acceptablePrice,
                    Order.OrderType.MarketIncrease
                );

                sizeDeltaUsd =
                    ((targetPos - currentPos) *
                        executionPrice *
                        (10 ** underlyingDecimals)) /
                    (10 ** SIREN_DECIMALS);

                _gmxPositionIncrease(
                    isLong,
                    sizeDeltaUsd,
                    initialCollateralDelta,
                    acceptablePrice
                );
            } else if (targetPos < currentPos) {
                // decrease position
                uint256 initialCollateralDelta;
                if (marginRequired < uint256(marginCurrent)) {
                    initialCollateralDelta =
                        uint256(marginCurrent) -
                        marginRequired;
                }

                uint256 sizeDeltaUsd = (position.sizeInUsd() *
                    (currentPos - targetPos)) / currentPos;

                _gmxPositionDecrease(
                    isLong,
                    sizeDeltaUsd,
                    initialCollateralDelta,
                    acceptablePrice
                );
            }

            if (isLong) {
                isLong = false;
            } else {
                break;
            }
        }
    }

    /// @notice Deposit collateral to a product
    function _depositCollateral(
        bool isLong,
        uint256 amount,
        uint256 acceptablePrice
    ) internal {
        if (amount == 0) return;

        uint256 poolBalance = IHedgedPool(hedgedPool).getCollateralBalance();
        if (amount > poolBalance) {
            // pool doesn't have enough collateral, move all we can
            amount = poolBalance;
        }

        _gmxDepositCollateral(isLong, amount, acceptablePrice);
    }

    /// @notice Withdraw collateral from a product
    /// @dev It withdraws directly to the hedged pool
    function _withdrawCollateral(
        bool isLong,
        uint256 amount,
        uint256 acceptablePrice
    ) internal {
        if (amount == 0) return;

        _gmxWithdrawCollateral(isLong, amount, acceptablePrice);
    }

    function _gmxPositionIncrease(
        bool isLong,
        uint256 sizeDeltaUsd,
        uint256 initialCollateralDelta,
        uint256 acceptablePrice
    ) internal {
        IOrderUtils.CreateOrderParamsAddresses
            memory createOrderParamAddresses = _createOrderParamAddresses();

        IOrderUtils.CreateOrderParamsNumbers
            memory createOrderParamNumbers = _createOrderParamNumbers(
                sizeDeltaUsd,
                initialCollateralDelta,
                0,
                acceptablePrice
            );

        Order.OrderType ordertype = Order.OrderType.MarketIncrease;

        IExchangeRouter(exchangeRouter).sendWnt(
            orderVault,
            tx.gasprice * ORDER_GAS_LIMIT
        );
        //Can probably alter this to always use the collateral token instead of passing as param
        _sendTokens(address(collateralToken), sizeDeltaUsd);

        bytes32 key = _createMarketOrder(
            createOrderParamAddresses,
            createOrderParamNumbers,
            Order.OrderType.MarketIncrease,
            Order.DecreasePositionSwapType.NoSwap,
            isLong,
            false,
            0
        );

        keys.push(key);
    }

    function _gmxPositionDecrease(
        bool isLong,
        uint256 sizeDeltaUsd,
        uint256 initialCollateralDelta,
        uint256 acceptablePrice
    ) internal {
        //TODO: Calculate
        uint256 minOutputAmount = 0;
        IOrderUtils.CreateOrderParamsAddresses
            memory createOrderParamAddresses = _createOrderParamAddresses();

        IOrderUtils.CreateOrderParamsNumbers
            memory createOrderParamNumbers = _createOrderParamNumbers(
                sizeDeltaUsd,
                initialCollateralDelta,
                minOutputAmount,
                acceptablePrice
            );

        Order.OrderType ordertype = Order.OrderType.MarketIncrease;

        bytes32 key = _createMarketOrder(
            createOrderParamAddresses,
            createOrderParamNumbers,
            Order.OrderType.MarketIncrease,
            Order.DecreasePositionSwapType.NoSwap,
            isLong,
            false,
            0
        );

        keys.push(key);
    }

    function _gmxDepositCollateral(
        bool isLong,
        uint256 amount,
        uint256 acceptablePrice
    ) internal {
        uint256 sizeDeltaUSD = 0;
        uint256 initialCollateralDeltaAmount = 0;
        uint256 minOutputAmount = 0;

        IOrderUtils.CreateOrderParamsAddresses
            memory createOrderParamAddresses = _createOrderParamAddresses();

        IOrderUtils.CreateOrderParamsNumbers
            memory createOrderParamNumbers = _createOrderParamNumbers(
                sizeDeltaUSD,
                initialCollateralDeltaAmount,
                minOutputAmount,
                acceptablePrice
            );

        Order.OrderType ordertype = Order.OrderType.MarketIncrease;

        IExchangeRouter(exchangeRouter).sendWnt{
            value: tx.gasprice * ORDER_GAS_LIMIT
        }(orderVault, tx.gasprice * ORDER_GAS_LIMIT);
        //Can probably alter this to always use the collateral token instead of passing as param

        _sendTokens(address(collateralToken), amount);

        bytes32 key = _createMarketOrder(
            createOrderParamAddresses,
            createOrderParamNumbers,
            Order.OrderType.MarketIncrease,
            Order.DecreasePositionSwapType.NoSwap,
            isLong,
            false,
            0
        );

        keys.push(key);
    }

    function _gmxWithdrawCollateral(
        bool isLong,
        uint256 amount,
        uint256 acceptablePrice
    ) internal {
        //TODO: Calculate
        uint256 minOutputAmount = 0;
        uint256 sizeDeltaUSD = 0;
        IOrderUtils.CreateOrderParamsAddresses
            memory createOrderParamAddresses = _createOrderParamAddresses();

        IOrderUtils.CreateOrderParamsNumbers
            memory createOrderParamNumbers = _createOrderParamNumbers(
                sizeDeltaUSD,
                amount,
                minOutputAmount, // have to find a way to calcualte the minOutputAmount
                acceptablePrice
            );

        Order.OrderType ordertype = Order.OrderType.MarketIncrease;

        bytes32 key = _createMarketOrder(
            createOrderParamAddresses,
            createOrderParamNumbers,
            Order.OrderType.MarketIncrease,
            Order.DecreasePositionSwapType.NoSwap,
            isLong,
            false,
            0
        );

        (key);
    }

    function _calculateAdjustedExecutionPrice(
        Position.Props memory position,
        MarketUtils.MarketPrices calldata prices,
        bool isLong,
        uint256 sizeDeltaUsd,
        uint256 initialCollateralDelta,
        uint256 acceptablePrice,
        Order.OrderType orderType
    ) internal returns (uint256) {
        // Order.Props.Flags.isLong(isLong) long = isLong;
        PositionUtils.UpdatePositionParams
            memory updateOrderParams = PositionUtils.UpdatePositionParams(
                executOrderParamContracts,
                marketProps,
                Order.Props(
                    _orderParamAddresses(),
                    _orderParamNumbers(
                        sizeDeltaUsd,
                        initialCollateralDelta,
                        0,
                        acceptablePrice,
                        orderType
                    ),
                    Order.Flags(isLong, false, false)
                ),
                bytes32(0),
                position,
                bytes32(0),
                Order.SecondaryOrderType.None
            );

        (, , , uint256 executionPrice) = IGMXUtils(gmxUtils).getExecutionPrice(
            updateOrderParams,
            prices.indexTokenPrice
        );

        return executionPrice;
    }

    function _getPositionKey(
        address account,
        bool isLong
    ) internal returns (bytes32) {
        bytes32 key = keccak256(
            abi.encode(account, market, collateralToken, isLong)
        );
        return key;
    }

    function _getMarginRequired(
        uint256 size, // in underlyingDecimals
        uint256 price
    ) internal returns (uint256) {
        return
            (size * price) /
            leverage /
            (10 ** (GMX_DECIMALS - collateralDecimals));
    }

    // increase order:
    //     - long: executionPrice should be smaller than acceptablePrice
    //     - short: executionPrice should be larger than acceptablePrice

    // decrease order:
    //     - long: executionPrice should be larger than acceptablePrice
    //     - short: executionPrice should be smaller than acceptablePrice
    function _getAcceptablePrice(
        uint256 price,
        bool isIncrease,
        bool isLong
    ) internal returns (uint256) {
        uint256 priceDiff = (price * ACCEPTABLE_PRICE_THRESHOLD) / 100;
        if (isIncrease) {
            if (isLong) {
                return price + priceDiff;
            } else {
                return price - priceDiff;
            }
        } else {
            if (isLong) {
                return price - priceDiff;
            } else {
                return price + priceDiff;
            }
        }
    }

    function _getMarketPrices()
        internal
        view
        returns (MarketUtils.MarketPrices memory)
    {
        uint256 indexTokenPrice;
        uint256 longTokenPrice;
        uint256 shortTokenPrice;
        bool hasPrice;
        (hasPrice, indexTokenPrice) = IGMXUtils(gmxUtils).getPriceFeedPrice(
            dataStore,
            marketProps.indexToken
        );
        require(hasPrice, "!indexTokenPrice");

        (hasPrice, longTokenPrice) = IGMXUtils(gmxUtils).getPriceFeedPrice(
            dataStore,
            marketProps.longToken
        );
        require(hasPrice, "!longTokenPrice");

        (hasPrice, shortTokenPrice) = IGMXUtils(gmxUtils).getPriceFeedPrice(
            dataStore,
            marketProps.shortToken
        );
        require(hasPrice, "!shortTokenPrice");

        return (
            MarketUtils.MarketPrices(
                Price.Props(indexTokenPrice, indexTokenPrice),
                Price.Props(longTokenPrice, longTokenPrice),
                Price.Props(shortTokenPrice, shortTokenPrice)
            )
        );
    }
}

