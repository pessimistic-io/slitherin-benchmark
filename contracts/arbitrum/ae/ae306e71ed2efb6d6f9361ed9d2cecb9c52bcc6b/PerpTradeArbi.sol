// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Commands} from "./Commands.sol";
import {Errors} from "./Errors.sol";
import {PerpTradeStorage} from "./PerpTradeStorage.sol";
import {IAccount} from "./interfaces_IAccount.sol";
import {IERC20} from "./IERC20.sol";
import {IGmxOrderBook} from "./IGmxOrderBook.sol";
import {IGmxReader} from "./IGmxReader.sol";
import {IGmxVault} from "./IGmxVault.sol";
import {ICapOrders} from "./ICapOrders.sol";
import {IMarketStore} from "./IMarketStore.sol";
import {IOperator} from "./IOperator.sol";
import {IGmxPositionRouter} from "./IGmxPositionRouter.sol";

contract PerpTradeArbi is PerpTradeStorage {
    /*//////////////////////////////////////////////////////////////
                             CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _operator) PerpTradeStorage(_operator) {}

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice execute the type of trade
    /// @dev can only be called by `Q` or `Vault`
    /// @param command the command of the ddex protocol from `Commands` library
    /// @param data encoded data of parameters depending on the ddex
    /// @param isOpen bool to check if the trade is an increase or a decrease trade
    function execute(uint256 command, bytes calldata data, bool isOpen) external payable onlyQorVault {
        if (command == Commands.CAP) {
            _cap(data, isOpen);
        } else if (command == Commands.GMX) {
            _gmx(data, isOpen);
        } else if (command == Commands.CROSS_CHAIN) {
            _crossChain(data);
        } else if (command == Commands.MODIFY_ORDER) {
            _modifyOrder(data, isOpen);
        } else if (command == Commands.CLAIM_REWARDS) {
            _claimRewards(data);
        } else {
            revert Errors.CommandMisMatch();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _cap(bytes memory data, bool isOpen) internal {
        // decode the data
        (address account,, ICapOrders.Order memory order, uint256 tpPrice, uint256 slPrice) =
            abi.decode(data, (address, uint96, ICapOrders.Order, uint256, uint256));

        if (account == address(0)) revert Errors.ZeroAddress();
        order.asset = IOperator(operator).getAddress("DEFAULTSTABLECOIN");

        // calculate the approval amount and approve the token
        if (isOpen) {
            address capFundStore = IOperator(operator).getAddress("CAPFUNDSTORE");
            address capMarketStore = IOperator(operator).getAddress("CAPMARKETSTORE");
            uint256 BPS_DIVIDER = 10000;
            bytes memory tokenApprovalData =
                abi.encodeWithSignature("approve(address,uint256)", capFundStore, order.margin);
            IAccount(account).execute(order.asset, tokenApprovalData, 0);

            IMarketStore.Market memory market = IMarketStore(capMarketStore).get(order.market);
            uint256 maxLeverage = market.maxLeverage;
            uint256 size = order.size;
            uint256 margin = order.margin;
            uint256 leverage = (size * 1e18) / margin;
            uint256 fee = (size * market.fee) / BPS_DIVIDER;
            order.margin = margin - fee;
            if (leverage >= maxLeverage * 1e18) {
                order.size = order.margin * maxLeverage;
            }
        }
        // Make the execute from account
        bytes memory tradeData = abi.encodeCall(ICapOrders.submitOrder, (order, tpPrice, slPrice));
        address capOrders = IOperator(operator).getAddress("CAPORDERS");
        IAccount(account).execute(capOrders, tradeData, 0);

        emit CapExecute(account, order, tpPrice, slPrice);
    }

    function _gmx(bytes calldata data, bool isOpen) internal {
        address depositToken = IOperator(operator).getAddress("DEFAULTSTABLECOIN");
        address gmxRouter = IOperator(operator).getAddress("GMXROUTER");
        address gmxOrderBook = IOperator(operator).getAddress("GMXORDERBOOK");
        address gmxPositionRouter = IOperator(operator).getAddress("GMXPOSITIONROUTER");
        uint256 fee = IGmxPositionRouter(gmxPositionRouter).minExecutionFee();

        if (isOpen) {
            GmxOpenOrderParams memory params;
            params = abi.decode(data, (GmxOpenOrderParams));
            if (params.account == address(0)) revert Errors.ZeroAddress();
            if (params.triggerPrice < 1) revert Errors.ZeroAmount();
            if (params.leverage < 1) revert Errors.ZeroAmount();

            uint96 balance = uint96(IERC20(depositToken).balanceOf(params.account));
            if (params.amount > balance) params.amount = balance;
            {
                bytes memory tokenApprovalData =
                    abi.encodeWithSignature("approve(address,uint256)", gmxRouter, params.amount);
                IAccount(params.account).execute(depositToken, tokenApprovalData, 0);
            }

            if (params.needApproval) {
                bytes memory pluginApprovalData;
                pluginApprovalData = abi.encodeWithSignature("approvePlugin(address)", gmxOrderBook);
                IAccount(params.account).execute(gmxRouter, pluginApprovalData, 0);
                pluginApprovalData = abi.encodeWithSignature("approvePlugin(address)", gmxPositionRouter);
                IAccount(params.account).execute(gmxRouter, pluginApprovalData, 0);
            }

            if (params.isLimit) {
                bytes memory tradeData = abi.encodeWithSignature(
                    "createIncreaseOrder(address[],uint256,address,uint256,uint256,address,bool,uint256,bool,uint256,bool)",
                    getGmxPath(false, params.tradeDirection, depositToken, params.tradeToken),
                    params.amount,
                    params.tradeToken,
                    0,
                    uint256(params.leverage * params.amount) * 1e18,
                    params.tradeDirection ? params.tradeToken : depositToken,
                    params.tradeDirection,
                    uint256(params.triggerPrice) * 1e22,
                    !params.tradeDirection,
                    fee,
                    false
                );
                IAccount(params.account).execute{value: fee}(gmxOrderBook, tradeData, fee);
            } else {
                bytes memory tradeData = abi.encodeWithSignature(
                    "createIncreasePosition(address[],address,uint256,uint256,uint256,bool,uint256,uint256,bytes32,address)",
                    getGmxPath(false, params.tradeDirection, depositToken, params.tradeToken), // path in case theres a swap
                    params.tradeToken, // the asset for which the position needs to be opened
                    params.amount, // the collateral amount
                    0, // the min amount of tradeToken in case of long and usdc in case of short for swap
                    uint256(params.leverage * params.amount) * 1e18, // size including the leverage to open a position, in 1e30 units
                    params.tradeDirection, // direction of the execute, true - long, false - short
                    uint256(params.triggerPrice) * 1e22, // the price at which the manager wants to open a position, in 1e30 units
                    fee, // min execution fee, `Gmx.PositionRouter.minExecutionFee()`
                    params.referralCode, // referral code
                    address(0) // an optional callback contract, this contract will be called on request execution or cancellation
                );
                IAccount(params.account).execute{value: fee}(gmxPositionRouter, tradeData, fee);
            }
            emit GmxOpenOrderExecute(
                params.account,
                params.amount,
                params.leverage,
                params.tradeToken,
                params.tradeDirection,
                params.isLimit,
                params.triggerPrice,
                params.needApproval,
                params.referralCode
            );
        } else {
            GmxCloseOrderParams memory params;
            params = abi.decode(data, (GmxCloseOrderParams));
            if (params.account == address(0)) revert Errors.ZeroAddress();
            if (params.triggerPrice < 1) revert Errors.ZeroAmount();

            if (params.isLimit) {
                bytes memory tradeData = abi.encodeWithSignature(
                    "createDecreaseOrder(address,uint256,address,uint256,bool,uint256,bool)",
                    params.tradeToken, // the asset used for the position
                    params.sizeDelta, // size of the position, in 1e30 units
                    params.tradeDirection ? params.tradeToken : depositToken, // if long, then collateral is baseToken, if short then collateral usdc
                    params.collateralDelta, // the amount of collateral to withdraw
                    params.tradeDirection, // the direction of the exisiting position
                    uint256(params.triggerPrice) * 1e22, // the price at which the manager wants to close the position, in 1e30 units
                    // depends on whether its a take profit order or a stop loss order
                    // if tp, tradeDirection ? true : false
                    // if sl, tradeDirection ? false: true
                    params.triggerAboveThreshold
                );
                IAccount(params.account).execute{value: fee + 1}(gmxOrderBook, tradeData, fee + 1);
            } else {
                bytes memory tradeData = abi.encodeWithSignature(
                    "createDecreasePosition(address[],address,uint256,uint256,bool,address,uint256,uint256,uint256,bool,address)",
                    getGmxPath(true, params.tradeDirection, depositToken, params.tradeToken), // path in case theres a swap
                    params.tradeToken, // the asset for which the position was opened
                    params.collateralDelta, // the amount of collateral to withdraw
                    params.sizeDelta, // the total size which has to be closed, in 1e30 units
                    params.tradeDirection, // the direction of the exisiting position
                    params.account, // address of the receiver after closing the position
                    uint256(params.triggerPrice) * 1e22, // the price at which the manager wants to close the position, in 1e30 units
                    0, // min output token amount
                    fee + 1, // min execution fee = `Gmx.PositionRouter.minExecutionFee() + 1`
                    false, // _withdrawETH, true if the amount recieved should be in ETH
                    address(0) // an optional callback contract, this contract will be called on request execution or cancellation
                );
                IAccount(params.account).execute{value: fee + 1}(gmxPositionRouter, tradeData, fee + 1);
            }
            emit GmxCloseOrderExecute(
                params.account,
                params.collateralDelta,
                params.tradeToken,
                params.sizeDelta,
                params.tradeDirection,
                params.isLimit,
                params.triggerPrice,
                params.triggerAboveThreshold
            );
        }
    }

    function _crossChain(bytes calldata data) internal {
        bytes memory lifiData;
        address account;
        address token;
        uint256 amount;

        (account, token, amount, lifiData) = abi.decode(data, (address, address, uint256, bytes));

        if (account == address(0)) revert Errors.ZeroAddress();
        if (token == address(0)) revert Errors.ZeroAddress();
        if (amount < 1) revert Errors.ZeroAmount();
        if (lifiData.length == 0) revert Errors.ExchangeDataMismatch();

        address crossChainRouter = IOperator(operator).getAddress("CROSSCHAINROUTER");
        bytes memory tokenApprovalData = abi.encodeWithSignature("approve(address,uint256)", crossChainRouter, amount);
        IAccount(account).execute(token, tokenApprovalData, 0);
        IAccount(account).execute{value: msg.value}(crossChainRouter, lifiData, msg.value);
        emit CrossChainExecute(account, token, amount, lifiData);
    }

    function _modifyOrder(bytes calldata data, bool isCancel) internal {
        (address account,, uint256 command, Order orderType, bytes memory orderData) =
            abi.decode(data, (address, uint256, uint256, Order, bytes));
        address adapter;
        address tradeToken; // purchase token (path[pat.lenfth - 1] while createIncreseOrder)
        uint256 executionFeeRefund;
        uint256 purchaseTokenAmount;
        address[] memory tradeTokens;
        uint256[] memory purchaseTokenAmounts;
        bytes memory actionData;

        if (isCancel) {
            uint256 orderId;
            uint256[] memory increaseOrders;
            uint256[] memory decreaseOrders;
            if (command == Commands.CAP) {
                if (orderType == Order.CANCEL_MULTIPLE) {
                    (increaseOrders) = abi.decode(orderData, (uint256[]));
                    actionData = abi.encodeWithSignature("cancelOrders(uint256[])", increaseOrders);
                    emit CapCancelMultipleOrdersExecute(account, increaseOrders);
                } else {
                    (orderId) = abi.decode(orderData, (uint256));
                    actionData = abi.encodeWithSignature("cancelOrder(uint256)", orderId);
                    emit CapCancelOrderExecute(account, orderId);
                }
                adapter = IOperator(operator).getAddress("CAPORDERS");
            } else if (command == Commands.GMX) {
                adapter = IOperator(operator).getAddress("GMXORDERBOOK");
                (orderId) = abi.decode(orderData, (uint256));
                if (orderType == Order.CANCEL_INCREASE) {
                    tradeTokens = new address[](1);
                    purchaseTokenAmounts = new uint256[](1);
                    actionData = abi.encodeWithSignature("cancelIncreaseOrder(uint256)", orderId);
                    (tradeToken, purchaseTokenAmount,,,,,,, executionFeeRefund) =
                        IGmxOrderBook(adapter).getIncreaseOrder(account, orderId);
                    tradeTokens[0] = tradeToken;
                    purchaseTokenAmounts[0] = purchaseTokenAmount;
                    emit GmxCancelOrderExecute(account, orderId);
                } else if (orderType == Order.CANCEL_DECREASE) {
                    (,,,,,,, executionFeeRefund) = IGmxOrderBook(adapter).getDecreaseOrder(account, orderId);
                    actionData = abi.encodeWithSignature("cancelDecreaseOrder(uint256)", orderId);
                    emit GmxCancelOrderExecute(account, orderId);
                } else if (orderType == Order.CANCEL_MULTIPLE) {
                    (increaseOrders, decreaseOrders) = abi.decode(orderData, (uint256[], uint256[]));
                    tradeTokens = new address[](increaseOrders.length);
                    purchaseTokenAmounts = new uint256[](increaseOrders.length);
                    actionData = abi.encodeWithSignature(
                        "cancelMultiple(uint256[],uint256[],uint256[])",
                        new uint[](0), // swapOrderIndexes,
                        increaseOrders,
                        decreaseOrders
                    );
                    {
                        address account = account;
                        uint256 _executionFeeRefund;
                        for (uint256 i = 0; i < decreaseOrders.length;) {
                            (,,,,,,, _executionFeeRefund) =
                                IGmxOrderBook(adapter).getDecreaseOrder(account, decreaseOrders[i]);
                            executionFeeRefund += _executionFeeRefund;
                            unchecked {
                                ++i;
                            }
                        }
                        for (uint256 i = 0; i < increaseOrders.length;) {
                            (tradeToken, purchaseTokenAmount,,,,,,, _executionFeeRefund) =
                                IGmxOrderBook(adapter).getIncreaseOrder(account, increaseOrders[i]);
                            tradeTokens[i] = tradeToken;
                            purchaseTokenAmounts[i] = purchaseTokenAmount;
                            executionFeeRefund += _executionFeeRefund;
                            unchecked {
                                ++i;
                            }
                        }
                    }
                    emit GmxCancelMultipleOrdersExecute(account, increaseOrders, decreaseOrders);
                }
            } else {
                revert Errors.CommandMisMatch();
            }
        } else {
            if (command == Commands.CAP) {
                (uint256 cancelOrderId, bytes memory capOrderData) = abi.decode(orderData, (uint256, bytes));
                bytes memory cancelOrderData = abi.encodeWithSignature("cancelOrder(uint256)", cancelOrderId);
                address capOrders = IOperator(operator).getAddress("CAPORDERS");
                IAccount(account).execute(capOrders, cancelOrderData, 0);
                if (orderType == Order.UPDATE_INCREASE) {
                    _cap(capOrderData, true);
                } else if (orderType == Order.UPDATE_DECREASE) {
                    _cap(capOrderData, false);
                } else {
                    revert Errors.CommandMisMatch();
                }
                emit CapCancelOrderExecute(account, cancelOrderId);
            } else if (command == Commands.GMX) {
                uint256 orderIndex;
                uint256 collateralDelta;
                uint256 sizeDelta;
                uint256 triggerPrice;
                bool triggerAboveThreshold;
                if (orderType == Order.UPDATE_INCREASE) {
                    (orderIndex, sizeDelta, triggerPrice, triggerAboveThreshold) =
                        abi.decode(orderData, (uint256, uint256, uint256, bool));
                    actionData = abi.encodeWithSignature(
                        "updateIncreaseOrder(uint256,uint256,uint256,bool)",
                        orderIndex,
                        sizeDelta,
                        triggerPrice,
                        triggerAboveThreshold
                    );
                } else if (orderType == Order.UPDATE_DECREASE) {
                    (orderIndex, collateralDelta, sizeDelta, triggerPrice, triggerAboveThreshold) =
                        abi.decode(orderData, (uint256, uint256, uint256, uint256, bool));
                    actionData = abi.encodeWithSignature(
                        "updateDecreaseOrder(uint256,uint256,uint256,uint256,bool)",
                        orderIndex,
                        collateralDelta,
                        sizeDelta,
                        triggerPrice,
                        triggerAboveThreshold
                    );
                }
                adapter = IOperator(operator).getAddress("GMXORDERBOOK");
                emit GmxModifyOrderExecute(
                    account, orderType, orderIndex, collateralDelta, sizeDelta, triggerPrice, triggerAboveThreshold
                );
            } else {
                revert Errors.CommandMisMatch();
            }
        }
        // TODO check on updateIncrease order too
        if (actionData.length > 0) IAccount(account).execute(adapter, actionData, 0);
        if (executionFeeRefund > 0) {
            address admin = IOperator(operator).getAddress("ADMIN");
            IAccount(account).execute(admin, "", executionFeeRefund);
        }
        for (uint256 i = 0; i < tradeTokens.length;) {
            _swap(tradeTokens[i], purchaseTokenAmounts[i], account);
            unchecked {
                ++i;
            }
        }
    }

    function _claimRewards(bytes calldata data) internal {
        (address account, uint256 command, bytes[] memory rewardData) = abi.decode(data, (address, uint256, bytes[]));
        address treasury = IOperator(operator).getAddress("TREASURY");
        address token;
        uint256 rewardAmount;

        if (command == Commands.CAP) {
            token = IOperator(operator).getAddress("ARBTOKEN");
            address capRewards = IOperator(operator).getAddress("CAPREWARDS");
            rewardAmount = IERC20(token).balanceOf(account);
            if (rewardData[0].length > 0) IAccount(account).execute(capRewards, rewardData[0], 0);
            rewardAmount = IERC20(token).balanceOf(account) - rewardAmount;
        } else if (command == Commands.GMX) {
            token = IOperator(operator).getAddress("WRAPPEDTOKEN");
            rewardAmount = IERC20(token).balanceOf(account);
        } else {
            revert Errors.CommandMisMatch();
        }

        if (rewardAmount > 0) {
            IAccount(account).execute(
                token, abi.encodeWithSignature("transfer(address,uint256)", treasury, rewardAmount), 0
            );
        }
    }

    function _swap(address tradeToken, uint256 purchaseTokenAmount, address account) internal {
        address depositToken = IOperator(operator).getAddress("DEFAULTSTABLECOIN");
        address gmxReader = IOperator(operator).getAddress("GMXREADER");
        address gmxVault = IOperator(operator).getAddress("GMXVAULT");
        address gmxRouter = IOperator(operator).getAddress("GMXROUTER");

        if (tradeToken != depositToken && purchaseTokenAmount > 0) {
            // TODO discuss what to do on cancelMultiple increase orders?? loop or use multi execute ??
            address[] memory path = new address[](2);
            path[0] = tradeToken;
            path[1] = depositToken;

            // TODO check maxAmount In logic ??
            (uint256 minOut,) =
                IGmxReader(gmxReader).getAmountOut(IGmxVault(gmxVault), path[0], path[1], purchaseTokenAmount);

            // TODO revert if minOut == 0
            uint256 ethToSend;
            bytes memory swapData;

            if (tradeToken == IOperator(operator).getAddress("WRAPPEDTOKEN")) {
                ethToSend = purchaseTokenAmount;
                swapData = abi.encodeWithSignature(
                    "swapETHToTokens(address[],uint256,address)",
                    path,
                    minOut,
                    account //  receiver
                );
            } else {
                bytes memory tokenApprovalData =
                    abi.encodeWithSignature("approve(address,uint256)", gmxRouter, purchaseTokenAmount);
                IAccount(account).execute(tradeToken, tokenApprovalData, 0);
                swapData = abi.encodeWithSignature(
                    "swap(address[],uint256,uint256,address)",
                    path,
                    purchaseTokenAmount, // amountIn
                    minOut,
                    account //  receiver
                );
            }
            IAccount(account).execute(gmxRouter, swapData, ethToSend);
        }
    }

    receive() external payable {}
}

