// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "./GlobalReentrancyGuard.sol";

import "./ExchangeUtils.sol";
import "./RoleModule.sol";
import "./FeatureUtils.sol";
import "./CallbackUtils.sol";

import "./AdlUtils.sol";
import "./LiquidationUtils.sol";

import "./Market.sol";
import "./MarketToken.sol";

import "./Order.sol";
import "./OrderVault.sol";
import "./OrderUtils.sol";

import "./Oracle.sol";
import "./OracleModule.sol";
import "./EventEmitter.sol";

import "./IReferralStorage.sol";

// @title BaseOrderHandler
// @dev Base contract for shared order handler functions
contract BaseOrderHandler is GlobalReentrancyGuard, RoleModule, OracleModule {
    using SafeCast for uint256;
    using Order for Order.Props;
    using Array for uint256[];

    EventEmitter public immutable eventEmitter;
    OrderVault public immutable orderVault;
    SwapHandler public immutable swapHandler;
    Oracle public immutable oracle;
    IReferralStorage public immutable referralStorage;

    constructor(
        RoleStore _roleStore,
        DataStore _dataStore,
        EventEmitter _eventEmitter,
        OrderVault _orderVault,
        Oracle _oracle,
        SwapHandler _swapHandler,
        IReferralStorage _referralStorage
    ) RoleModule(_roleStore) GlobalReentrancyGuard(_dataStore) {
        eventEmitter = _eventEmitter;
        orderVault = _orderVault;
        oracle = _oracle;
        swapHandler = _swapHandler;
        referralStorage = _referralStorage;
    }

    // @dev get the BaseOrderUtils.ExecuteOrderParams to execute an order
    // @param key the key of the order to execute
    // @param oracleParams OracleUtils.SetPricesParams
    // @param keeper the keeper executing the order
    // @param startingGas the starting gas
    // @return the required BaseOrderUtils.ExecuteOrderParams params to execute the order
    function _getExecuteOrderParams(
        bytes32 key,
        OracleUtils.SetPricesParams memory oracleParams,
        address keeper,
        uint256 startingGas,
        Order.SecondaryOrderType secondaryOrderType
    ) internal view returns (BaseOrderUtils.ExecuteOrderParams memory) {
        BaseOrderUtils.ExecuteOrderParams memory params;

        params.key = key;
        params.order = OrderStoreUtils.get(dataStore, key);
        params.swapPathMarkets = MarketUtils.getSwapPathMarkets(
            dataStore,
            params.order.swapPath()
        );

        params.contracts.dataStore = dataStore;
        params.contracts.eventEmitter = eventEmitter;
        params.contracts.orderVault = orderVault;
        params.contracts.oracle = oracle;
        params.contracts.swapHandler = swapHandler;
        params.contracts.referralStorage = referralStorage;

        params.minOracleBlockNumbers = OracleUtils.getUncompactedOracleBlockNumbers(
            oracleParams.compactedMinOracleBlockNumbers,
            oracleParams.tokens.length
        );

        params.maxOracleBlockNumbers = OracleUtils.getUncompactedOracleBlockNumbers(
            oracleParams.compactedMaxOracleBlockNumbers,
            oracleParams.tokens.length
        );

        if (params.order.market() != address(0)) {
            params.market = MarketUtils.getEnabledMarket(params.contracts.dataStore, params.order.market());
        }

        params.keeper = keeper;
        params.startingGas = startingGas;

        params.secondaryOrderType = secondaryOrderType;

        return params;
    }
}

