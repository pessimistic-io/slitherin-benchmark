// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Commands} from "./Commands.sol";
import {Errors} from "./Errors.sol";
import {PerpTradeStorage} from "./PerpTradeStorage.sol";
import {IAccount} from "./interfaces_IAccount.sol";
import {IERC20} from "./IERC20.sol";
import {ICapOrders} from "./ICapOrders.sol";
import {IMarketStore} from "./IMarketStore.sol";
import {IAccount as IKwentaAccount} from "./interfaces_IAccount.sol";
import {IFactory as IKwentaFactory} from "./IFactory.sol";
import {IOperator} from "./IOperator.sol";

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
            _cap(data);
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

    function _cap(bytes memory data) internal {
        // decode the data
        (address account,, ICapOrders.Order memory order, uint256 tpPrice, uint256 slPrice) =
            abi.decode(data, (address, uint96, ICapOrders.Order, uint256, uint256));

        if (account == address(0)) revert Errors.ZeroAddress();
        // TODO (update tests to uncomment)
        // if (order.asset != IOperator(operator).getAddress("DEFAULTSTABLECOIN")) revert Errors.InputMismatch();

        // calculate the approval amount and approve the token
        IMarketStore.Market memory market = IMarketStore(MARKET_STORE).get(order.market);
        uint256 valueConsumed = order.margin + (order.size * market.fee) / BPS_DIVIDER;
        bytes memory tokenApprovalData = abi.encodeWithSignature("approve(address,uint256)", FUND_STORE, valueConsumed);
        IAccount(account).execute(order.asset, tokenApprovalData);

        // Make the execute from account
        bytes memory tradeData = abi.encodeCall(ICapOrders.submitOrder, (order, tpPrice, slPrice));
        IAccount(account).execute(ORDERS, tradeData);
    }

    function _gmx(bytes calldata data, bool isOpen) internal {
        if (isOpen) {
            (
                address account,
                uint96 amount,
                uint32 leverage,
                address tradeToken,
                bool tradeDirection,
                bool isLimit,
                int256 triggerPrice,
                bool needApproval,
                bytes32 referralCode
            ) = abi.decode(data, (address, uint96, uint32, address, bool, bool, int256, bool, bytes32));
            address depositToken = IOperator(operator).getAddress("DEFAULTSTABLECOIN");
            if (account == address(0)) revert Errors.ZeroAddress();
            if (triggerPrice < 1) revert Errors.ZeroAmount();
            if (leverage < 1) revert Errors.ZeroAmount();

            if (IERC20(depositToken).balanceOf(account) < amount) revert Errors.BalanceLessThanAmount();
            {
                bytes memory tokenApprovalData =
                    abi.encodeWithSignature("approve(address,uint256)", getGmxRouter(), amount);
                IAccount(account).execute(depositToken, tokenApprovalData);
            }

            if (needApproval) {
                address adapter = getGmxRouter();
                bytes memory pluginApprovalData;
                pluginApprovalData = abi.encodeWithSignature("approvePlugin(address)", getGmxOrderBook());
                IAccount(account).execute(adapter, pluginApprovalData);
                pluginApprovalData = abi.encodeWithSignature("approvePlugin(address)", getGmxPositionRouter());
                IAccount(account).execute(adapter, pluginApprovalData);
            }

            uint256 fee = getGmxFee();
            if (isLimit) {
                bytes memory tradeData = abi.encodeWithSignature(
                    "createIncreaseOrder(address[],uint256,address,uint256,uint256,address,bool,uint256,bool,uint256,bool)",
                    getPath(false, tradeDirection, depositToken, tradeToken),
                    amount,
                    tradeToken,
                    0,
                    uint256(leverage * amount) * 1e18,
                    tradeDirection ? tradeToken : depositToken,
                    tradeDirection,
                    uint256(triggerPrice) * 1e22,
                    !tradeDirection,
                    fee,
                    false
                );
                IAccount(account).execute{value: fee}(getGmxOrderBook(), tradeData);
            } else {
                bytes memory tradeData = abi.encodeWithSignature(
                    "createIncreasePosition(address[],address,uint256,uint256,uint256,bool,uint256,uint256,bytes32,address)",
                    getPath(false, tradeDirection, depositToken, tradeToken), // path in case theres a swap
                    tradeToken, // the asset for which the position needs to be opened
                    amount, // the collateral amount
                    0, // the min amount of tradeToken in case of long and usdc in case of short for swap
                    uint256(leverage * amount) * 1e18, // size including the leverage to open a position, in 1e30 units
                    tradeDirection, // direction of the execute, true - long, false - short
                    uint256(triggerPrice) * 1e22, // the price at which the manager wants to open a position, in 1e30 units
                    fee, // min execution fee, `Gmx.PositionRouter.minExecutionFee()`
                    referralCode, // referral code
                    address(0) // an optional callback contract, this contract will be called on request execution or cancellation
                );
                IAccount(account).execute{value: fee}(getGmxPositionRouter(), tradeData);
            }
        } else {
            (
                address account,
                uint96 collateralDelta,
                address tradeToken,
                uint256 sizeDelta,
                bool tradeDirection,
                bool isLimit,
                int256 triggerPrice,
                bool triggerAboveThreshold
            ) = abi.decode(data, (address, uint96, address, uint256, bool, bool, int256, bool));
            address depositToken = IOperator(operator).getAddress("DEFAULTSTABLECOIN");
            if (account == address(0)) revert Errors.ZeroAddress();
            if (triggerPrice < 1) revert Errors.ZeroAmount();

            uint256 fee = getGmxFee();
            if (isLimit) {
                bytes memory tradeData = abi.encodeWithSignature(
                    "createDecreaseOrder(address,uint256,address,uint256,bool,uint256,bool)",
                    tradeToken, // the asset used for the position
                    sizeDelta, // size of the position, in 1e30 units
                    tradeDirection ? tradeToken : depositToken, // if long, then collateral is baseToken, if short then collateral usdc
                    collateralDelta, // the amount of collateral to withdraw
                    tradeDirection, // the direction of the exisiting position
                    uint256(triggerPrice) * 1e22, // the price at which the manager wants to close the position, in 1e30 units
                    // depends on whether its a take profit order or a stop loss order
                    // if tp, tradeDirection ? true : false
                    // if sl, tradeDirection ? false: true
                    triggerAboveThreshold
                );
                IAccount(account).execute{value: fee + 1}(getGmxOrderBook(), tradeData);
            } else {
                bytes memory tradeData = abi.encodeWithSignature(
                    "createDecreasePosition(address[],address,uint256,uint256,bool,address,uint256,uint256,uint256,bool,address)",
                    getPath(true, tradeDirection, depositToken, tradeToken), // path in case theres a swap
                    tradeToken, // the asset for which the position was opened
                    collateralDelta, // the amount of collateral to withdraw
                    sizeDelta, // the total size which has to be closed, in 1e30 units
                    tradeDirection, // the direction of the exisiting position
                    account, // address of the receiver after closing the position
                    uint256(triggerPrice) * 1e22, // the price at which the manager wants to close the position, in 1e30 units
                    0, // min output token amount
                    getGmxFee() + 1, // min execution fee = `Gmx.PositionRouter.minExecutionFee() + 1`
                    false, // _withdrawETH, true if the amount recieved should be in ETH
                    address(0) // an optional callback contract, this contract will be called on request execution or cancellation
                );
                IAccount(account).execute{value: fee + 1}(getGmxPositionRouter(), tradeData);
            }
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

        bytes memory tokenApprovalData = abi.encodeWithSignature("approve(address,uint256)", CROSS_CHAIN_ROUTER, amount);
        IAccount(account).execute(token, tokenApprovalData);
        IAccount(account).execute{value: msg.value}(CROSS_CHAIN_ROUTER, lifiData);
    }

    function _modifyOrder(bytes calldata data, bool isCancel) internal {
        (address account,, uint256 command, Order orderType, bytes memory orderData) =
            abi.decode(data, (address, uint256, uint256, Order, bytes));
        address adapter;
        bytes memory actionData;

        if (isCancel) {
            if (command == Commands.CAP) {
                if (orderType == Order.CANCEL_MULTIPLE) {
                    (uint256[] memory orderIDs) = abi.decode(orderData, (uint256[]));
                    actionData = abi.encodeWithSignature("cancelOrders(uint256[])", orderIDs);
                } else {
                    (uint256 orderId) = abi.decode(orderData, (uint256));
                    actionData = abi.encodeWithSignature("cancelOrder(uint256)", orderId);
                }
                adapter = ORDERS;
            } else if (command == Commands.GMX) {
                (uint256 orderIndex) = abi.decode(orderData, (uint256));
                if (orderType == Order.CANCEL_INCREASE) {
                    actionData = abi.encodeWithSignature("cancelIncreaseOrder(uint256)", orderIndex);
                } else if (orderType == Order.CANCEL_DECREASE) {
                    actionData = abi.encodeWithSignature("cancelDecreaseOrder(uint256)", orderIndex);
                } else if (orderType == Order.CANCEL_MULTIPLE) {
                    (uint256[] memory increaseOrderIndexes, uint256[] memory decreaseOrderIndexes) =
                        abi.decode(orderData, (uint256[], uint256[]));
                    actionData = abi.encodeWithSignature(
                        "cancelMultiple(uint256[],uint256[],uint256[])",
                        new uint[](0), // swapOrderIndexes,
                        increaseOrderIndexes,
                        decreaseOrderIndexes
                    );
                }
                adapter = getGmxOrderBook();
            } else {
                revert Errors.CommandMisMatch();
            }
        } else {
            if (command == Commands.CAP) {
                (uint256 cancelOrderId, bytes memory capOrderData) = abi.decode(orderData, (uint256, bytes));
                bytes memory cancelOrderData = abi.encodeWithSignature("cancelOrder(uint256)", cancelOrderId);
                IAccount(account).execute(ORDERS, cancelOrderData);

                _cap(capOrderData);
            } else if (command == Commands.GMX) {
                if (orderType == Order.UPDATE_INCREASE) {
                    (uint256 _orderIndex, uint256 _sizeDelta, uint256 _triggerPrice, bool _triggerAboveThreshold) =
                        abi.decode(orderData, (uint256, uint256, uint256, bool));
                    actionData = abi.encodeWithSignature(
                        "updateIncreaseOrder(uint256,uint256,uint256,bool)",
                        _orderIndex,
                        _sizeDelta,
                        _triggerPrice,
                        _triggerAboveThreshold
                    );
                } else if (orderType == Order.UPDATE_DECREASE) {
                    (
                        uint256 _orderIndex,
                        uint256 _collateralDelta,
                        uint256 _sizeDelta,
                        uint256 _triggerPrice,
                        bool _triggerAboveThreshold
                    ) = abi.decode(orderData, (uint256, uint256, uint256, uint256, bool));
                    actionData = abi.encodeWithSignature(
                        "updateDecreaseOrder(uint256,uint256,uint256,uint256,bool)",
                        _orderIndex,
                        _collateralDelta,
                        _sizeDelta,
                        _triggerPrice,
                        _triggerAboveThreshold
                    );
                }
                adapter = getGmxOrderBook();
            } else {
                revert Errors.CommandMisMatch();
            }
        }
        if (actionData.length > 0) IAccount(account).execute(adapter, actionData);
    }

    function _claimRewards(bytes calldata data) internal {
        (address account, uint256 command, bytes[] memory rewardData) = abi.decode(data, (address, uint256, bytes[]));
        address treasury = IOperator(operator).getAddress("TREASURY");
        address token;
        uint256 rewardAmount;

        if (command == Commands.CAP) {
            token = rewards.ARB;
            rewardAmount = IERC20(token).balanceOf(account);
            if (rewardData[0].length > 0) IAccount(account).execute(rewards.REWARDS, rewardData[0]);
            rewardAmount = IERC20(token).balanceOf(account) - rewardAmount;
        } else if (command == Commands.GMX) {
            token = IOperator(operator).getAddress("WRAPPEDTOKEN");
            rewardAmount = IERC20(token).balanceOf(account);
        } else {
            revert Errors.CommandMisMatch();
        }

        if (rewardAmount > 0) {
            IAccount(account).execute(
                token, abi.encodeWithSignature("transfer(address,uint256)", treasury, rewardAmount)
            );
        }
    }

    receive() external payable {}
}

