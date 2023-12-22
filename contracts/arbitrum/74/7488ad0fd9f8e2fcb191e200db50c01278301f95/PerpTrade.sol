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

contract PerpTrade is PerpTradeStorage {
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
        } else if (command == Commands.KWENTA) {
            _kwenta(data, isOpen);
        } else if (command == Commands.CROSS_CHAIN) {
            _crossChain(data);
        } else if (command == Commands.MODIFY_ORDER) {
            _executeAction(data);
        } else if (command == Commands.CLAIM_REWARDS) {
            _executeAction(data);
        } else {
            revert Errors.CommandMisMatch();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _cap(bytes calldata data) internal {
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

    function _kwenta(bytes calldata data, bool isOpen) internal {
        (
            address account,
            uint96 amount,
            address kwentaAccount,
            bytes memory exchangeData,
            IKwentaAccount.Command[] memory commands,
            bytes[] memory bytesParams
        ) = abi.decode(data, (address, uint96, address, bytes, IKwentaAccount.Command[], bytes[]));

        if (account == address(0)) revert Errors.ZeroAddress();
        // TODO (update tests to uncomment)
        // if (amount < 1) revert Errors.ZeroAmount();
        // if (exchangeData.length == 0) revert Errors.ExchangeDataMismatch();

        address depositToken = IOperator(operator).getAddress("DEFAULTSTABLECOIN");
        address _kwentaFactory = getKwentaFactory();
        address sUSD = getSUSD();

        if (kwentaAccount == address(0)) {
            bytes memory createAccountData = abi.encodeWithSignature("newAccount()");
            IAccount(account).execute(_kwentaFactory, createAccountData);
            address[] memory accountsOwned = IKwentaFactory(_kwentaFactory).getAccountsOwnedBy(account);
            kwentaAccount = accountsOwned[0];
        }

        if (isOpen) {
            if (exchangeData.length > 0) {
                _swap(account, amount, depositToken, sUSD, exchangeData);
            }

            uint256 sUsdBalance = IERC20(sUSD).balanceOf(account);
            bytes memory tokenApprovalData =
                abi.encodeWithSignature("approve(address,uint256)", kwentaAccount, sUsdBalance);
            IAccount(account).execute(sUSD, tokenApprovalData);
        }

        if (commands.length > 0) {
            bytes memory tradeData = abi.encodeWithSignature("execute(uint8[],bytes[])", commands, bytesParams);
            IAccount(account).execute{value: msg.value}(kwentaAccount, tradeData);
        } else {
            // TODO check the 0.01 eth for gelato
            IAccount(account).execute{value: msg.value}(kwentaAccount, ""); // deposit ETH to cover gelato fees
        }

        if (!isOpen) {
            if (exchangeData.length > 0) {
                _swap(account, amount, sUSD, depositToken, exchangeData);
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

    function _swap(address account, uint96 amount, address tokenIn, address tokenOut, bytes memory exchangeData)
        internal
    {
        (address exchangeRouter, bytes memory routerData) = abi.decode(exchangeData, (address, bytes));

        uint256 balanceBefore = IERC20(tokenOut).balanceOf(account);

        bytes memory tokenApprovalData = abi.encodeWithSignature("approve(address,uint256)", exchangeRouter, amount);
        IAccount(account).execute(tokenIn, tokenApprovalData);

        IAccount(account).execute(exchangeRouter, routerData);
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(account);
        if (balanceAfter <= balanceBefore) revert Errors.BalanceLessThanAmount();
    }

    function _executeAction(bytes calldata data) internal {
        (address account, address adapter, bytes memory actionData) = abi.decode(data, (address, address, bytes));
        IAccount(account).execute(adapter, actionData);
    }

    receive() external payable {}
}

