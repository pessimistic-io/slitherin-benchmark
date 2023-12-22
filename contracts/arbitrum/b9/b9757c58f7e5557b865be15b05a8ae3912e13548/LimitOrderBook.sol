// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import { BlockContext } from "./BlockContext.sol";
import { AddressUpgradeable } from "./AddressUpgradeable.sol";
import { ECDSAUpgradeable } from "./ECDSAUpgradeable.sol";
import { EIP712Upgradeable } from "./EIP712Upgradeable.sol";
import { SignedSafeMathUpgradeable } from "./SignedSafeMathUpgradeable.sol";
import { SafeMathUpgradeable } from "./SafeMathUpgradeable.sol";
import { PerpMath } from "./PerpMath.sol";
import { PerpSafeCast } from "./PerpSafeCast.sol";
import { ILimitOrderBook } from "./ILimitOrderBook.sol";
import { IDelegateApproval } from "./IDelegateApproval.sol";
import { LimitOrderBookStorageV1 } from "./LimitOrderBookStorageV1.sol";
import { OwnerPausable } from "./OwnerPausable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { IClearingHouse } from "./IClearingHouse.sol";
import { IAccountBalance } from "./IAccountBalance.sol";
import { IVPool } from "./IVPool.sol";
import { DataTypes } from "./DataTypes.sol";

contract LimitOrderBook is
    ILimitOrderBook,
    IDelegateApproval,
    BlockContext,
    ReentrancyGuardUpgradeable,
    OwnerPausable,
    EIP712Upgradeable,
    LimitOrderBookStorageV1
{
    using AddressUpgradeable for address;
    using PerpMath for int256;
    using PerpMath for uint256;
    using PerpSafeCast for uint256;
    using SignedSafeMathUpgradeable for int256;
    using SafeMathUpgradeable for uint256;
    using SafeMathUpgradeable for uint8;

    // NOTE: remember to update typehash if you change LimitOrder struct
    // NOTE: cannot use `OrderType orderType` here, use `uint8 orderType` for enum instead
    // solhint-disable-next-line max-line-length
    // keccak256("LimitOrderParams(uint256 multiplier,uint8 orderType,uint256 nonce,address trader,address baseToken,bool isBaseToQuote,bool isExactInput,uint256 amount,uint256 oppositeAmountBound,uint256 deadline,uint256 triggerPrice,uint256 takeProfitPrice,uint256 stopLossPrice)");

    // solhint-disable-next-line func-name-mixedcase
    bytes32 public constant LIMIT_ORDER_TYPEHASH = 0xc840995b47c840ff0fc83762c5ec5f589a4c19037e2790c7eb9448e1d4f4c490;

    //
    // EXTERNAL NON-VIEW
    //

    function initialize(
        string memory name,
        string memory version,
        address clearingHouseArg,
        uint256 minOrderValueArg,
        uint256 feeOrderValueArg
    ) external initializer {
        __ReentrancyGuard_init();
        __OwnerPausable_init();
        __EIP712_init(name, version); // ex: "PerpCurieLimitOrder" and "1"

        // LOB_CHINC: ClearingHouse Is Not Contract
        require(clearingHouseArg.isContract(), "LOB_CHINC");
        _clearingHouse = clearingHouseArg;

        // LOB_ABINC: AccountBalance Is Not Contract
        address accountBalanceArg = IClearingHouse(_clearingHouse).getAccountBalance();
        require(accountBalanceArg.isContract(), "LOB_ABINC");
        _accountBalance = accountBalanceArg;

        // LOB_MOVMBGT0: MinOrderValue Must Be Greater Than Zero
        require(minOrderValueArg > 0, "LOB_MOVMBGT0");
        _minOrderValue = minOrderValueArg;

        _feeOrderValue = feeOrderValueArg;
    }

    function getClearingHouse() external view returns (address) {
        return _clearingHouse;
    }

    function getAccountBalance() external view returns (address) {
        return _accountBalance;
    }

    function getMinOrderValue() external view returns (uint256) {
        return _minOrderValue;
    }

    function getFeeOrderValue() external view returns (uint256) {
        return _feeOrderValue;
    }

    function setClearingHouse(address clearingHouseArg) external onlyOwner {
        // LOB_CHINC: ClearingHouse Is Not Contract
        require(clearingHouseArg.isContract(), "LOB_CHINC");
        _clearingHouse = clearingHouseArg;

        // LOB_ABINC: AccountBalance Is Not Contract
        address accountBalanceArg = IClearingHouse(_clearingHouse).getAccountBalance();
        require(accountBalanceArg.isContract(), "LOB_ABINC");
        _accountBalance = accountBalanceArg;

        emit ClearingHouseChanged(clearingHouseArg);
    }

    function setFeeOrderValue(uint256 feeOrderValueArg) external onlyOwner {
        _feeOrderValue = feeOrderValueArg;
        emit FeeOrderValueChanged(feeOrderValueArg);
    }

    function setMinOrderValue(uint256 minOrderValueArg) external onlyOwner {
        // LOB_MOVMBGT0: MinOrderValue Must Be Greater Than Zero
        require(minOrderValueArg > 0, "LOB_MOVMBGT0");
        _minOrderValue = minOrderValueArg;

        emit MinOrderValueChanged(minOrderValueArg);
    }

    /// @inheritdoc IDelegateApproval
    function canOpenPositionFor(address trader, address delegate) external view override returns (bool) {
        return true;
    }

    function fillLimitOrder(LimitOrderParams memory order, bytes memory signature) external override nonReentrant {
        address sender = _msgSender();

        // short term solution: mitigate that attacker can drain LimitOrderRewardVault
        // LOB_SMBE: Sender Must Be EOA
        require(!sender.isContract(), "LOB_SMBE");

        // check multiplier
        _checkMultiplier(order.baseToken, order.multiplier);

        (, bytes32 orderHash) = _verifySigner(order, signature);

        // LOB_OMBU: Order Must Be Unfilled
        require(_ordersStatus[orderHash] == ILimitOrderBook.OrderStatus.Unfilled, "LOB_OMBU");

        (int256 exchangedPositionSize, int256 exchangedPositionNotional, uint256 fee) = _fillLimitOrder(
            _msgSender(),
            order
        );

        if (
            (order.orderType == ILimitOrderBook.OrderType.LimitOrder ||
                order.orderType == ILimitOrderBook.OrderType.StopLimitOrder) &&
            (order.takeProfitPrice > 0 || order.stopLossPrice > 0)
        ) {
            ILimitOrderBook.LimitOrder memory storedOrder = ILimitOrderBook.LimitOrder({
                multiplier: order.multiplier,
                orderType: order.orderType,
                trader: order.trader,
                baseToken: order.baseToken,
                base: exchangedPositionSize,
                takeProfitPrice: order.takeProfitPrice,
                stopLossPrice: order.stopLossPrice
            });
            _orders[orderHash] = storedOrder;
            _ordersStatus[orderHash] = ILimitOrderBook.OrderStatus.Filled;
        } else {
            _ordersStatus[orderHash] = ILimitOrderBook.OrderStatus.Closed;
        }

        emit LimitOrderFilled(
            order.trader,
            order.baseToken,
            orderHash,
            uint8(order.orderType),
            sender, // keeper
            exchangedPositionSize,
            exchangedPositionNotional,
            fee,
            _feeOrderValue
        );
    }

    /// @inheritdoc ILimitOrderBook
    function cancelLimitOrder(LimitOrderParams memory order) external override {
        // LOB_OSMBS: Order's Signer Must Be Sender
        require(_msgSender() == order.trader, "LOB_OSMBS");

        // we didn't require `signature` as input like fillLimitOrder(),
        // so trader can actually cancel an order that is not existed
        bytes32 orderHash = getOrderHash(order);

        // LOB_OMBU: Order Must Be Unfilled or Filled
        require(
            _ordersStatus[orderHash] == ILimitOrderBook.OrderStatus.Unfilled ||
                _ordersStatus[orderHash] == ILimitOrderBook.OrderStatus.Filled,
            "LOB_OMBUOF"
        );

        _ordersStatus[orderHash] = ILimitOrderBook.OrderStatus.Cancelled;

        int256 positionSize;
        int256 positionNotional;
        if (order.isBaseToQuote) {
            if (order.isExactInput) {
                positionSize = order.amount.neg256();
                positionNotional = order.oppositeAmountBound.toInt256();
            } else {
                positionSize = order.oppositeAmountBound.neg256();
                positionNotional = order.amount.toInt256();
            }
        } else {
            if (order.isExactInput) {
                positionSize = order.oppositeAmountBound.toInt256();
                positionNotional = order.amount.neg256();
            } else {
                positionSize = order.amount.toInt256();
                positionNotional = order.oppositeAmountBound.neg256();
            }
        }

        emit LimitOrderCancelled(
            order.trader,
            order.baseToken,
            orderHash,
            uint8(order.orderType),
            positionSize,
            positionNotional
        );
    }

    /// @inheritdoc ILimitOrderBook
    function closeLimitOrder(LimitOrderParams memory order) external override {
        address sender = _msgSender();

        // short term solution: mitigate that attacker can drain LimitOrderRewardVault
        // LOB_SMBE: Sender Must Be EOA
        require(!sender.isContract(), "LOB_SMBE");

        // check multiplier
        _checkMultiplier(order.baseToken, order.multiplier);

        // we didn't require `signature` as input like fillLimitOrder(),
        // so trader can actually cancel an order that is not existed
        bytes32 orderHash = getOrderHash(order);

        // LOB_OMBU: Order Must Be Filled
        require(_ordersStatus[orderHash] == ILimitOrderBook.OrderStatus.Filled, "LOB_OMBF");

        uint256 markPrice = _getPrice(order.baseToken);
        //
        ILimitOrderBook.LimitOrder memory storedOrder = _orders[orderHash];
        // LOB_ITSP: invalid take profilt or stop loss price
        require(
            (storedOrder.base > 0 &&
                ((order.takeProfitPrice > 0 && markPrice >= order.takeProfitPrice) ||
                    (order.stopLossPrice > 0 && markPrice <= order.stopLossPrice))) ||
                (storedOrder.base < 0 &&
                    ((order.takeProfitPrice > 0 && markPrice <= order.takeProfitPrice) ||
                        (order.stopLossPrice > 0 && markPrice >= order.stopLossPrice))),
            "LOB_ITSP"
        );
        bool isBaseToQuote = storedOrder.base > 0 ? true : false;
        (uint256 base, uint256 quote, uint256 fee) = IClearingHouse(_clearingHouse).openPositionFor(
            _msgSender(),
            _feeOrderValue,
            order.trader,
            DataTypes.OpenPositionParams({
                baseToken: order.baseToken,
                isBaseToQuote: isBaseToQuote,
                isExactInput: isBaseToQuote,
                amount: storedOrder.base.abs(),
                oppositeAmountBound: 0,
                deadline: _blockTimestamp() + 60,
                sqrtPriceLimitX96: 0,
                referralCode: ""
            })
        );
        // LOB_OVTS: Order Value Too Small
        require(quote >= _minOrderValue, "LOB_OVTS");

        int256 exchangedPositionSize;
        int256 exchangedPositionNotional;
        if (order.isBaseToQuote) {
            exchangedPositionSize = base.neg256();
            exchangedPositionNotional = quote.toInt256();
        } else {
            exchangedPositionSize = base.toInt256();
            exchangedPositionNotional = quote.neg256();
        }

        _ordersStatus[orderHash] = ILimitOrderBook.OrderStatus.Closed;

        emit LimitOrderClosed(
            order.trader,
            order.baseToken,
            orderHash,
            uint8(order.orderType),
            sender, // keeper
            exchangedPositionSize,
            exchangedPositionNotional,
            fee,
            _feeOrderValue
        );
    }

    //
    // PUBLIC VIEW
    //

    function getOrderHash(LimitOrderParams memory order) public view override returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(LIMIT_ORDER_TYPEHASH, order)));
    }

    function getOrderStatus(bytes32 orderHash) external view override returns (ILimitOrderBook.OrderStatus) {
        return _ordersStatus[orderHash];
    }

    //
    // INTERNAL NON-VIEW
    //

    function _fillLimitOrder(
        address msgSender,
        LimitOrderParams memory order
    ) internal returns (int256, int256, uint256) {
        _verifyTriggerPrice(order);

        (uint256 base, uint256 quote, uint256 fee) = IClearingHouse(_clearingHouse).openPositionFor(
            msgSender,
            _feeOrderValue,
            order.trader,
            DataTypes.OpenPositionParams({
                baseToken: order.baseToken,
                isBaseToQuote: order.isBaseToQuote,
                isExactInput: order.isExactInput,
                amount: order.amount,
                oppositeAmountBound: order.oppositeAmountBound,
                deadline: order.deadline,
                sqrtPriceLimitX96: 0,
                referralCode: ""
            })
        );

        // LOB_OVTS: Order Value Too Small
        require(quote >= _minOrderValue, "LOB_OVTS");

        int256 exchangedPositionSize;
        int256 exchangedPositionNotional;
        if (order.isBaseToQuote) {
            exchangedPositionSize = base.neg256();
            exchangedPositionNotional = quote.toInt256();
        } else {
            exchangedPositionSize = base.toInt256();
            exchangedPositionNotional = quote.neg256();
        }

        return (exchangedPositionSize, exchangedPositionNotional, fee);
    }

    //
    // INTERNAL VIEW
    //

    function _verifySigner(
        LimitOrderParams memory order,
        bytes memory signature
    ) internal view returns (address, bytes32) {
        bytes32 orderHash = getOrderHash(order);
        address signer = ECDSAUpgradeable.recover(orderHash, signature);

        // LOB_SINT: Signer Is Not Trader
        require(signer == order.trader, "LOB_SINT");

        return (signer, orderHash);
    }

    function _verifyTriggerPrice(LimitOrderParams memory order) internal view {
        uint256 triggeredPrice = _getPrice(order.baseToken);

        // we need to make sure the price has reached trigger price.
        // however, we can only know whether index price has reached trigger price,
        // we didn't know whether market price has reached trigger price

        if (order.orderType == ILimitOrderBook.OrderType.LimitOrder) {
            // LOB_ITP: Invalid Trigger Price
            require(order.triggerPrice > 0, "LOB_ITP");

            if (order.isBaseToQuote) {
                //short: triggeredPrice >=  order.triggerPrice
                // LOB_SLOTPNM: Sell Limit Order Trigger Price Not Matched
                require(triggeredPrice >= order.triggerPrice, "LOB_SLOTPNM");
            } else {
                //long: triggeredPrice  <=  order.triggerPrice
                // LOB_BLOTPNM: Buy Limit Order Trigger Price Not Matched
                require(triggeredPrice <= order.triggerPrice, "LOB_BLOTPNM");
            }
        } else if (order.orderType == ILimitOrderBook.OrderType.TPSLOrder) {
            // LOB_ITP: Invalid Trigger Price
            require(order.takeProfitPrice > 0 || order.stopLossPrice > 0, "LOB_TSP");

            if (order.isBaseToQuote) {
                // old long
                // stoploss        long        takeprofit
                if (
                    (order.stopLossPrice > 0 && triggeredPrice <= order.stopLossPrice) ||
                    (order.takeProfitPrice > 0 && triggeredPrice >= order.takeProfitPrice)
                ) {
                    //trigger order
                } else {
                    // LOB_SSLOTPNM: TPSL Not Matched
                    revert("LOB_TPSLNM");
                }
            } else {
                // old short
                // takeprofit        short        stoploss
                if (
                    (order.stopLossPrice > 0 && triggeredPrice >= order.stopLossPrice) ||
                    (order.takeProfitPrice > 0 && triggeredPrice <= order.takeProfitPrice)
                ) {
                    //trigger order
                } else {
                    // LOB_SSLOTPNM: TPSL Not Matched
                    revert("LOB_TPSLNM");
                }
            }
        } else if (order.orderType == ILimitOrderBook.OrderType.StopLimitOrder) {
            // LOB_ITP: Invalid Trigger Price
            require(order.triggerPrice > 0, "LOB_ITP");

            if (order.isBaseToQuote) {
                //short : triggeredPrice <= order.triggerPrice
                // LOB_SSLIOTPNM: Sell Stop limit Order Trigger Price Not Matched
                require(triggeredPrice <= order.triggerPrice, "LOB_SSLIOTPNM");
            } else {
                //long : triggeredPrice >= order.triggerPrice
                // LOB_BSLIOTPNM: Buy Stop Limit Order Trigger Price Not Matched
                require(triggeredPrice >= order.triggerPrice, "LOB_BSLIOTPNM");
            }
        }
    }

    function _getPrice(address baseToken) internal view returns (uint256) {
        return IAccountBalance(_accountBalance).getReferencePrice(baseToken);
    }

    function getPrice(address baseToken) internal view returns (uint256) {
        return _getPrice(baseToken);
    }

    function _checkMultiplier(address baseToken, uint256 multiplier) internal view {
        (uint256 longMultiplier, uint256 shortMultiplier) = IAccountBalance(_accountBalance).getMarketMultiplier(
            baseToken
        );
        // LOB_NMM: not matched multiplier
        require(multiplier == (longMultiplier + shortMultiplier), "LOB_NMM");
    }
}

