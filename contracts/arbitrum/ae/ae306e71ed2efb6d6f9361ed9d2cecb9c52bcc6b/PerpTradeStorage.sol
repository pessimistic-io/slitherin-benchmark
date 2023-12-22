// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Errors} from "./Errors.sol";
import {IOperator} from "./IOperator.sol";
import {ICapOrders} from "./ICapOrders.sol";
import {IAccount as IKwentaAccount} from "./interfaces_IAccount.sol";

contract PerpTradeStorage {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    enum Order {
        UPDATE_INCREASE,
        UPDATE_DECREASE,
        CANCEL_INCREASE,
        CANCEL_DECREASE,
        CANCEL_MULTIPLE
    }

    struct GmxOpenOrderParams {
        address account;
        uint96 amount;
        uint32 leverage;
        address tradeToken;
        bool tradeDirection;
        bool isLimit;
        int256 triggerPrice;
        bool needApproval;
        bytes32 referralCode;
    }

    struct GmxCloseOrderParams {
        address account;
        uint96 collateralDelta;
        address tradeToken;
        uint256 sizeDelta;
        bool tradeDirection;
        bool isLimit;
        int256 triggerPrice;
        bool triggerAboveThreshold;
    }

    address public operator;

    /*//////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    event InitPerpTrade(address indexed operator);
    event CapExecute(address indexed account, ICapOrders.Order order, uint256 tpPrice, uint256 slPrice);
    event GmxOpenOrderExecute(
        address indexed account,
        uint96 amount,
        uint32 leverage,
        address indexed tradeToken,
        bool tradeDirection,
        bool isLimit,
        int256 triggerPrice,
        bool needApproval,
        bytes32 indexed referralCode
    );
    event GmxCloseOrderExecute(
        address indexed account,
        uint96 collateralDelta,
        address indexed tradeToken,
        uint256 sizeDelta,
        bool tradeDirection,
        bool isLimit,
        int256 triggerPrice,
        bool triggerAboveThreshold
    );
    event CrossChainExecute(address indexed account, address indexed token, uint256 amount, bytes lifiData);
    event KwentaExecute(
        address indexed account,
        uint96 amount,
        address kwentaAccount,
        bytes exchangeData,
        IKwentaAccount.Command[] commands,
        bytes[] bytesParams
    );
    event KwentaModifyOrder(address indexed account, uint256 command, bytes orderData);
    event CapCancelOrderExecute(address indexed account, uint256 orderId);
    event GmxCancelOrderExecute(address indexed account, uint256 orderId);
    event CapCancelMultipleOrdersExecute(address indexed account, uint256[] orderIds);
    event GmxCancelMultipleOrdersExecute(address indexed account, uint256[] increaseOrders, uint256[] decreaseOrders);
    event GmxModifyOrderExecute(
        address indexed account,
        Order orderType,
        uint256 orderIndex,
        uint256 collateralDelta,
        uint256 sizeDelta,
        uint256 triggerPrice,
        bool triggerAboveThreshold
    );

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR/MODIFIERS
    //////////////////////////////////////////////////////////////*/

    constructor(address _operator) {
        operator = _operator;
        emit InitPerpTrade(_operator);
    }

    modifier onlyOwner() {
        address owner = IOperator(operator).getAddress("OWNER");
        if (msg.sender != owner) revert Errors.NotOwner();
        _;
    }

    modifier onlyQorVault() {
        address q = IOperator(operator).getAddress("Q");
        address vault = IOperator(operator).getAddress("VAULT");
        if ((msg.sender != q) && (msg.sender != vault)) revert Errors.NoAccess();
        _;
    }

    function getGmxPath(bool _isClose, bool _tradeDirection, address _depositToken, address _tradeToken)
        internal
        pure
        returns (address[] memory _path)
    {
        if (!_tradeDirection) {
            // for short, the collateral is in stable coin,
            // so the path only needs depositToken since there's no swap
            _path = new address[](1);
            _path[0] = _depositToken;
        } else {
            // for long, the collateral is in the tradeToken,
            // we swap from usdc to tradeToken when opening and vice versa
            _path = new address[](2);
            _path[0] = _isClose ? _tradeToken : _depositToken;
            _path[1] = _isClose ? _depositToken : _tradeToken;
        }
    }
}

