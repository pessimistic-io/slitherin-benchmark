// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";
import "./BaseOrderUtils.sol";
import "./IDatastore.sol";
import "./Keys.sol";
import "./IPriceFeed.sol";
import "./Precision.sol";
import "./IDatastore.sol";
import "./Enum.sol";
import "./IModuleManager.sol";
import "./ISmartAccountFactory.sol";
import "./IWNT.sol";
import "./IExchangeRouter.sol";

//1. Arbitrum configs
//2. Operator should approve WETH to this contract
contract Gmxv2OrderModule is Ownable {
    address public operator;
    uint256 public ethPrice;
    uint256 public ethPriceMultiplier = 10 ** 12;

    uint256 private constant MAXPRICEBUFFERACTOR = 120; // 120%, require(inputETHPrice < priceFeedPrice * 120%)
    uint256 private constant PRICEUPDATEACTOR = 115; // 115%, threshhold to update the ETH priceFeed price
    uint256 private constant MAXTXGASRATIO = 50; // 50%, require(inputTxGas/ExecutionFeeGasLimit < 50%)

    address private constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address private constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    IDataStore private constant DATASTORE = IDataStore(0xFD70de6b91282D8017aA4E741e9Ae325CAb992d8);
    bytes32 private constant REFERRALCODE = 0x74726164616f0000000000000000000000000000000000000000000000000000; //tradao
    address private constant REFERRALSTORAGE = 0xe6fab3F0c7199b0d34d7FbE83394fc0e0D06e99d;
    ISmartAccountFactory private constant BICONOMY_FACTORY =
        ISmartAccountFactory(0x000000a56Aaca3e9a4C479ea6b6CD0DbcB6634F5);
    bytes private constant SETREFERRALCODECALLDATA =
        abi.encodeWithSignature("setTraderReferralCodeByUser(bytes32)", REFERRALCODE);
    bytes private constant MODULE_SETUP_DATA = abi.encodeWithSignature("getModuleAddress()"); //0xf004f2f9
    address private constant BICONOMY_MODULE_SETUP = 0x2692b7d240288fEEA31139d4067255E31Fe71a79; // todo reconfirm
    bytes4 private constant OWNERSHIPT_INIT_SELECTOR = 0x2ede3bc0; //bytes4(keccak256("initForSmartAccount(address)"))
    address private constant DEFAULT_ECDSA_OWNERSHIP_MODULE = 0x0000001c5b32F37F5beA87BDD5374eB2aC54eA8e;
    bytes32 private constant ETH_MULTIPLIER_KEY = 0x007b50887d7f7d805ee75efc0a60f8aaee006442b047c7816fc333d6d083cae0; //keccak256(abi.encode(keccak256(abi.encode("PRICE_FEED_MULTIPLIER")), address(WETH)))
    bytes32 private constant ETH_PRICE_FEED_KEY = 0xb1bca3c71fe4192492fabe2c35af7a68d4fc6bbd2cfba3e35e3954464a7d848e; //keccak256(abi.encode(keccak256(abi.encode("PRICE_FEED")), address(WETH)))
    uint256 private ETH_MULTIPLIER = 10 ** 18;
    uint256 private USDC_MULTIPLIER = 10 ** 6;
    address private constant ORDER_VAULT = 0x31eF83a530Fde1B38EE9A18093A333D8Bbbc40D5;
    IExchangeRouter private constant EXCHANGE_ROUTER = IExchangeRouter(0x7C68C7866A64FA2160F78EEaE12217FFbf871fa8);

    event OperatorTransferred(address indexed previousOperator, address indexed newOperator);
    event UpdateEthPrice(uint256 newPrice);
    event NewSmartAccount(address indexed creator, address userEOA, address smartAccount);
    event OrderCreated(
        address indexed aa,
        uint256 indexed positionId,
        uint256 sizeDelta,
        uint256 collateralDelta,
        uint256 acceptablePrice,
        bytes32 orderKey,
        uint256 triggerPrice
    );
    event OrderCreationFailed(
        address indexed aa,
        uint256 indexed positionId,
        uint256 sizeDelta,
        uint256 collateralDelta,
        uint256 acceptablePrice,
        uint256 triggerPrice,
        Enum.FailureReason reason
    );
    event OrderCancelled(address indexed aa, bytes32 orderKey);

    error UnsupportedOrderType();
    error OrderCreationError(
        address aa,
        uint256 positionId,
        uint256 sizeDelta,
        uint256 collateralDelta,
        uint256 acceptablePrice,
        uint256 triggerPrice
    );

    struct OrderParamBase {
        uint256 positionId;
        uint256 _ethPrice;
        uint256 _txGas;
        address market;
        Order.OrderType orderType;
        bool isLong;
    }

    struct OrderParam {
        uint256 sizeDeltaUsd;
        uint256 initialCollateralDeltaAmount; //for increase, indicate USDC transfer amount; for decrease, set to createOrderParams
        uint256 acceptablePrice;
        address smartAccount;
    }

    /**
     * @dev Only allows addresses with the operator role to call the function.
     */
    modifier onlyOperator() {
        require(msg.sender == operator, "401");
        _;
    }

    //Owner should be transfer to a TimelockController
    constructor(address initialOperator) Ownable(msg.sender) {
        operator = initialOperator;
    }

    function transferOperator(address newOperator) external onlyOwner {
        address oldOperator = operator;
        operator = newOperator;
        emit OperatorTransferred(oldOperator, newOperator);
    }

    function deployAA(address userEOA) external returns (bool isSuccess) {
        uint256 startGas = gasleft();

        address aa = _deployAA(userEOA);
        setReferralCode(aa);
        emit NewSmartAccount(msg.sender, userEOA, aa);
        isSuccess = true;

        if (msg.sender == operator) {
            uint256 gasUsed = _adjustGasUsage(DATASTORE, startGas - gasleft());
            //transfer gas fee to TinySwap...
            isSuccess = _aaTransferUsdc(aa, _calcUsdc(gasUsed * tx.gasprice, ethPrice), operator);
        }
    }

    //cancel single order
    function cancelOrder(address smartAccount, bytes32 key) external onlyOperator returns (bool success) {
        uint256 startGas = gasleft();
        require(key > 0, "key");

        bytes memory data = abi.encodeWithSelector(EXCHANGE_ROUTER.cancelOrder.selector, key);
        success = IModuleManager(smartAccount).execTransactionFromModule(
            address(EXCHANGE_ROUTER), 0, data, Enum.Operation.Call
        );
        if (success) {
            emit OrderCancelled(smartAccount, key);
        }

        uint256 gasUsed = _adjustGasUsage(DATASTORE, startGas - gasleft());
        _aaTransferEth(smartAccount, gasUsed * tx.gasprice, operator);
    }

    //single order, could contain trigger price
    function newOrder(uint256 triggerPrice, OrderParamBase memory _orderBase, OrderParam memory _orderParam)
        external
        onlyOperator
        returns (bytes32 orderKey)
    {
        (uint256 _txGasFee, uint256 _executionGasFee) =
            _calcGas(_orderBase._ethPrice, _orderBase.orderType, _orderBase._txGas);
        return _newOrder(_txGasFee, _executionGasFee, triggerPrice, _orderBase, _orderParam);
    }

    /**
     *   copy trading orders.
     *   do off chain check before every call:
     *   1. check if very aa's module is enabled
     *   2. check aa's balance
     *   3. get latest eth price, estimate gas
     *   4. do simulation call
     */
    function newOrders(OrderParamBase memory _orderBase, OrderParam[] memory orderParams)
        external
        onlyOperator
        returns (bytes32[] memory orderKeys)
    {
        (uint256 _txGasFee, uint256 _executionGasFee) =
            _calcGas(_orderBase._ethPrice, _orderBase.orderType, _orderBase._txGas);
        uint256 len = orderParams.length;
        orderKeys = new bytes32[](len);

        for (uint256 i; i < len; i++) {
            OrderParam memory _orderParam = orderParams[i];
            orderKeys[i] = _newOrder(_txGasFee, _executionGasFee, 0, _orderBase, _orderParam);
        }
    }

    function _newOrder(
        uint256 _txGasFee,
        uint256 _executionGasFee,
        uint256 triggerPrice,
        OrderParamBase memory _orderBase,
        OrderParam memory _orderParam
    ) internal returns (bytes32 orderKey) {
        bool isIncreaseOrder = BaseOrderUtils.isIncreaseOrder(_orderBase.orderType);
        bool isSuccess = _payGas(_orderParam.smartAccount, _txGasFee, _executionGasFee, _orderBase._ethPrice);
        if (!isSuccess) {
            emit OrderCreationFailed(
                _orderParam.smartAccount,
                _orderBase.positionId,
                _orderParam.sizeDeltaUsd,
                _orderParam.initialCollateralDeltaAmount,
                _orderParam.acceptablePrice,
                triggerPrice,
                Enum.FailureReason.PayGasFailed
            );
            return 0;
        }

        if (isIncreaseOrder && _orderParam.initialCollateralDeltaAmount > 0) {
            isSuccess = _aaTransferUsdc(_orderParam.smartAccount, _orderParam.initialCollateralDeltaAmount, ORDER_VAULT);
            if (!isSuccess) {
                emit OrderCreationFailed(
                    _orderParam.smartAccount,
                    _orderBase.positionId,
                    _orderParam.sizeDeltaUsd,
                    _orderParam.initialCollateralDeltaAmount,
                    _orderParam.acceptablePrice,
                    triggerPrice,
                    Enum.FailureReason.TransferCollateralToVaultFailed
                );
                return 0;
            }
        }

        //build orderParam
        BaseOrderUtils.CreateOrderParams memory cop;
        _buildOrderCommonPart(_executionGasFee, _orderBase.market, _orderBase.orderType, _orderBase.isLong, cop);
        _buildOrderCustomPart(_orderParam, cop);
        cop.numbers.triggerPrice = triggerPrice;
        if (!isIncreaseOrder) {
            cop.numbers.initialCollateralDeltaAmount = _orderParam.initialCollateralDeltaAmount;
        }

        //send order
        orderKey = _aaCreateOrder(cop);
        if (orderKey == 0) {
            if (isIncreaseOrder && _orderParam.initialCollateralDeltaAmount > 0) {
                //protect user's collateral.
                revert OrderCreationError(
                    _orderParam.smartAccount,
                    _orderBase.positionId,
                    _orderParam.sizeDeltaUsd,
                    _orderParam.initialCollateralDeltaAmount,
                    _orderParam.acceptablePrice,
                    triggerPrice
                );
            } else {
                emit OrderCreationFailed(
                    _orderParam.smartAccount,
                    _orderBase.positionId,
                    _orderParam.sizeDeltaUsd,
                    _orderParam.initialCollateralDeltaAmount,
                    _orderParam.acceptablePrice,
                    triggerPrice,
                    Enum.FailureReason.CreateOrderFailed
                );
            }
        } else {
            emit OrderCreated(
                _orderParam.smartAccount,
                _orderBase.positionId,
                _orderParam.sizeDeltaUsd,
                _orderParam.initialCollateralDeltaAmount,
                _orderParam.acceptablePrice,
                orderKey,
                triggerPrice
            );
        }
    }

    //return orderKey == 0 if failed.
    function _aaCreateOrder(BaseOrderUtils.CreateOrderParams memory cop) internal returns (bytes32 orderKey) {
        bytes memory data = abi.encodeWithSelector(EXCHANGE_ROUTER.createOrder.selector, cop);
        (bool success, bytes memory returnData) = IModuleManager(cop.addresses.receiver)
            .execTransactionFromModuleReturnData(address(EXCHANGE_ROUTER), 0, data, Enum.Operation.Call);
        if (success) {
            orderKey = bytes32(returnData);
        }
    }

    function _calcGas(uint256 _ethPrice, Order.OrderType orderType, uint256 _txGas)
        internal
        returns (uint256 txGasFee, uint256 executionGasFee)
    {
        require(_ethPrice * 100 < ethPrice * MAXPRICEBUFFERACTOR, "ethPrice");
        if (_ethPrice * 100 >= ethPrice * PRICEUPDATEACTOR) {
            updateEthPrice();
        }

        uint256 executionFeeGasLimit = getExecutionFeeGasLimit(orderType);
        require(_txGas * 100 < executionFeeGasLimit * MAXTXGASRATIO, "txGas");

        txGasFee = _txGas * tx.gasprice;
        executionGasFee = executionFeeGasLimit * tx.gasprice;
    }

    function _payGas(address aa, uint256 txGasFee, uint256 executionFee, uint256 _ethPrice)
        internal
        returns (bool isSuccess)
    {
        if (aa.balance < txGasFee + executionFee) {
            if (IERC20(WETH).balanceOf(operator) < executionFee) {
                return false;
            }
            //transfer gas fee and execution fee USDC from AA to TinySwap
            isSuccess = _aaTransferUsdc(aa, _calcUsdc(txGasFee + executionFee, _ethPrice), operator);
        } else {
            //convert ETH to WETH to operator
            bytes memory data = abi.encodeWithSelector(IWNT(WETH).depositTo.selector, operator);
            isSuccess =
                IModuleManager(aa).execTransactionFromModule(WETH, txGasFee + executionFee, data, Enum.Operation.Call);
        }
        //transfer execution fee WETH from operator to GMX Vault
        if (isSuccess) {
            require(IERC20(WETH).transferFrom(operator, ORDER_VAULT, executionFee), "op eth");
        }
    }

    function _buildOrderCommonPart(
        uint256 executionFee,
        address market,
        Order.OrderType orderType,
        bool isLong,
        BaseOrderUtils.CreateOrderParams memory params
    ) internal pure {
        params.numbers.executionFee = executionFee;

        params.addresses.market = market;
        params.orderType = orderType;
        params.isLong = isLong;
    }

    function _buildOrderCustomPart(OrderParam memory _orderParam, BaseOrderUtils.CreateOrderParams memory params)
        internal
        pure
    {
        params.addresses.receiver = _orderParam.smartAccount;
        params.addresses.initialCollateralToken = USDC;

        params.numbers.sizeDeltaUsd = _orderParam.sizeDeltaUsd;
        params.numbers.acceptablePrice = _orderParam.acceptablePrice;

        params.decreasePositionSwapType = Order.DecreasePositionSwapType.SwapPnlTokenToCollateralToken;
        params.shouldUnwrapNativeToken = true;
    }

    function _aaTransferUsdc(address aa, uint256 usdcAmount, address to) internal returns (bool isSuccess) {
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, usdcAmount);
        isSuccess = IModuleManager(aa).execTransactionFromModule(USDC, 0, data, Enum.Operation.Call);
    }

    function _calcUsdc(uint256 ethAmount, uint256 _ethPrice) internal view returns (uint256 usdcAmount) {
        return ethAmount * _ethPrice * USDC_MULTIPLIER / ETH_MULTIPLIER / ethPriceMultiplier;
    }

    function _aaTransferEth(address aa, uint256 ethAmount, address to) internal returns (bool isSuccess) {
        isSuccess = IModuleManager(aa).execTransactionFromModule(to, ethAmount, "", Enum.Operation.Call);
    }

    function _deployAA(address userEOA) internal returns (address) {
        uint256 index = uint256(uint160(userEOA));
        address aa = BICONOMY_FACTORY.deployCounterFactualAccount(BICONOMY_MODULE_SETUP, MODULE_SETUP_DATA, index);
        bytes memory data = abi.encodeWithSelector(
            IModuleManager.setupAndEnableModule.selector,
            DEFAULT_ECDSA_OWNERSHIP_MODULE,
            abi.encodeWithSelector(OWNERSHIPT_INIT_SELECTOR, userEOA)
        );
        bool isSuccess = IModuleManager(aa).execTransactionFromModule(aa, 0, data, Enum.Operation.Call);
        require(isSuccess, "500");

        return aa;
    }

    function getExecutionFeeGasLimit(Order.OrderType orderType) public view returns (uint256) {
        return _adjustGasLimitForEstimate(DATASTORE, _estimateExecuteOrderGasLimit(DATASTORE, orderType));
    }

    // @dev adjust the estimated gas limit to help ensure the execution fee is sufficient during
    // the actual execution
    // @param dataStore DataStore
    // @param estimatedGasLimit the estimated gas limit
    function _adjustGasLimitForEstimate(IDataStore dataStore, uint256 estimatedGasLimit)
        internal
        view
        returns (uint256)
    {
        uint256 baseGasLimit = dataStore.getUint(Keys.ESTIMATED_GAS_FEE_BASE_AMOUNT);
        uint256 multiplierFactor = dataStore.getUint(Keys.ESTIMATED_GAS_FEE_MULTIPLIER_FACTOR);
        uint256 gasLimit = baseGasLimit + Precision.applyFactor(estimatedGasLimit, multiplierFactor);
        return gasLimit;
    }

    // @dev the estimated gas limit for orders
    function _estimateExecuteOrderGasLimit(IDataStore dataStore, Order.OrderType orderType)
        internal
        view
        returns (uint256)
    {
        if (BaseOrderUtils.isIncreaseOrder(orderType)) {
            return dataStore.getUint(Keys.increaseOrderGasLimitKey());
        }

        if (BaseOrderUtils.isDecreaseOrder(orderType)) {
            return dataStore.getUint(Keys.decreaseOrderGasLimitKey()) + dataStore.getUint(Keys.singleSwapGasLimitKey());
        }

        revert UnsupportedOrderType();
    }

    // @dev adjust the gas usage to pay operator
    // @param dataStore DataStore
    // @param gasUsed the amount of gas used
    function _adjustGasUsage(IDataStore dataStore, uint256 gasUsed) internal view returns (uint256) {
        // the gas cost is estimated based on the gasprice of the request txn
        // the actual cost may be higher if the gasprice is higher in the execution txn
        // the multiplierFactor should be adjusted to account for this
        uint256 multiplierFactor = dataStore.getUint(Keys.EXECUTION_GAS_FEE_MULTIPLIER_FACTOR);
        uint256 gasLimit = Precision.applyFactor(gasUsed, multiplierFactor);
        return gasLimit;
    }

    // @dev get and update token price from Oracle
    function updateEthPrice() public returns (uint256 newPrice) {
        newPrice = getPriceFeedPrice(DATASTORE);
        ethPrice = newPrice;
        emit UpdateEthPrice(newPrice);
    }

    function getPriceFeedPrice(IDataStore dataStore) public view returns (uint256) {
        address priceFeedAddress = dataStore.getAddress(ETH_PRICE_FEED_KEY);
        IPriceFeed priceFeed = IPriceFeed(priceFeedAddress);

        (
            /* uint80 roundID */
            ,
            int256 _price,
            /* uint256 startedAt */
            ,
            /* uint256 updatedAt */
            ,
            /* uint80 answeredInRound */
        ) = priceFeed.latestRoundData();

        require(_price > 0, "priceFeed");

        uint256 price = SafeCast.toUint256(_price);
        uint256 precision = getPriceFeedMultiplier(dataStore);

        uint256 adjustedPrice = Precision.mulDiv(price, precision, Precision.FLOAT_PRECISION);

        return adjustedPrice;
    }

    // @dev get the multiplier value to convert the external price feed price to the price of 1 unit of the token
    // represented with 30 decimals
    // for example, if USDC has 6 decimals and a price of 1 USD, one unit of USDC would have a price of
    // 1 / (10 ^ 6) * (10 ^ 30) => 1 * (10 ^ 24)
    // if the external price feed has 8 decimals, the price feed price would be 1 * (10 ^ 8)
    // in this case the priceFeedMultiplier should be 10 ^ 46
    // the conversion of the price feed price would be 1 * (10 ^ 8) * (10 ^ 46) / (10 ^ 30) => 1 * (10 ^ 24)
    // formula for decimals for price feed multiplier: 60 - (external price feed decimals) - (token decimals)
    //
    // @param dataStore DataStore
    // @param token the token to get the price feed multiplier for
    // @return the price feed multipler
    function getPriceFeedMultiplier(IDataStore dataStore) public view returns (uint256) {
        uint256 multiplier = dataStore.getUint(ETH_MULTIPLIER_KEY);

        require(multiplier > 0, "500");

        return multiplier;
    }

    function updateEthPriceMultiplier() external {
        address priceFeedAddress = IDataStore(DATASTORE).getAddress(ETH_PRICE_FEED_KEY);
        IPriceFeed priceFeed = IPriceFeed(priceFeedAddress);
        uint256 priceFeedDecimal = uint256(IPriceFeed(priceFeed).decimals());
        ethPriceMultiplier = (10 ** priceFeedDecimal) * getPriceFeedMultiplier(DATASTORE) / (10 ** 30);
    }

    function setReferralCode(address smartAccount) public returns (bool isSuccess) {
        return IModuleManager(smartAccount).execTransactionFromModule(
            REFERRALSTORAGE, 0, SETREFERRALCODECALLDATA, Enum.Operation.Call
        );
    }
}

