// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import { IERC20 } from "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./EnumerableSet.sol";
import "./Ownable.sol";
import "./IClearingHouse.sol";
import "./INFTPerpOrder.sol";
import "./Decimal.sol";
import "./Errors.sol";
import { LibOrder } from "./LibOrder.sol";
import "./Structs.sol";

contract NFTPerpOrder is INFTPerpOrder, Ownable(), ReentrancyGuard(){
    using Decimal for Decimal.decimal;
    using LibOrder for Structs.Order;
    
    //ClearingHouse contract implementation
    IClearingHouse public immutable clearingHouse;
    //Fee Manager address
    address public immutable feeManager;
    //Management Fee(paid in eth)
    uint256 public managementFee;
    //mapping(Order Hash/Id -> Order)
    mapping(bytes32 => Structs.Order) public order;
    //mapping(Order Hash/Id -> bool)
    mapping(bytes32 => bool) public orderFulfilled;

    constructor(address _clearingHouse, address _feeManager){
        feeManager = _feeManager;
        clearingHouse = IClearingHouse(_clearingHouse);
    }


    //
    //      |============================================================================================|
    //      |        BUY/SELL        |     TYPE OF ORDER         |     PRICE LEVEL OF TRIGGER PRICE      |
    //      |============================================================================================|
    //      |          BUY           |    BUY LIMIT ORDER        |    Trigger Price < or = Latest Price  |
    //      |                        |    BUY STOP LOSS ORDER    |    Trigger Price > or = Latest Price  |
    //      |------------------------|---------------------------|---------------------------------------|
    //      |          SELL          |    SELL LIMIT ORDER       |    Trigger Price > or = Latest Price  |
    //      |                        |    SELL STOP LOSS ORDER   |    Trigger Price < or = Latest Price  |
    //      |============================================================================================|
    //
    ///@notice Creates a Market Order(Limit or StopLoss Order). 
    ///        - https://www.investopedia.com/terms/l/limitorder.asp
    ///        - https://www.investopedia.com/articles/stocks/09/use-stop-loss.asp
    ///@param _amm amm
    ///@param _orderType order type
    ///@param _expirationTimestamp order expiry timestamp
    ///@param _triggerPrice trigger/execution price of an order
    ///@param _slippage slippage(0 for any slippage)
    ///@param _leverage leverage, only use when creating a BUY/SELL limit order
    ///@param _quoteAssetAmount quote asset amount, only use when creating a BUY/SELL limit order
    ///@return orderHash
    function createOrder(
        IAmm _amm,
        Structs.OrderType _orderType, 
        uint64 _expirationTimestamp,
        uint256 _triggerPrice,
        Decimal.decimal memory _slippage,
        Decimal.decimal memory _leverage,
        Decimal.decimal memory _quoteAssetAmount
    ) external payable override nonReentrant() returns(bytes32 orderHash){
        address _account = msg.sender;
        orderHash = _getOrderHash(_amm, _orderType, _account);
        // checks if order is valid
        _validOrder(_expirationTimestamp, orderHash);
        
        Structs.Order storage _order = order[orderHash];
        _order.trigger = _triggerPrice;
        _order.position.amm = _amm;
        _order.position.slippage = _slippage;

        if(_orderType == Structs.OrderType.SELL_LO || _orderType == Structs.OrderType.BUY_LO){
            // Limit Order quote asset amount should be gt zero
            if(_quoteAssetAmount.toUint() == 0)
                revert Errors.InvalidQuoteAssetAmount();

            _order.position.quoteAssetAmount = _quoteAssetAmount;
            _order.position.leverage = _leverage;

        } else {
            int256 positionSize = LibOrder.getPositionSize(_amm, _account, clearingHouse);
            // Positon size cannot be equal to zero (No open position)
            if(positionSize == 0) 
                revert Errors.NoOpenPositon();
            // store quote asset amount of user's current open position (open notional)
            _order.position.quoteAssetAmount = LibOrder.getPositionNotional(_amm, _account, clearingHouse);
        }

        uint256 _detail;
        //                             [256 bits]
        //        ===========================================================
        //        |  32 bits     |      160 bits      |       64 bits       |  
        //        -----------------------------------------------------------
        //        | orderType    |      account       | expirationTimestamp |
        //        ===========================================================

        _detail = uint256(_orderType) << 248 | (uint224(uint160(_account)) << 64 | _expirationTimestamp);

        _order.detail = _detail;
       
        // trasnsfer fees to Fee-Manager Contract
        _transferFee();

        orderFulfilled[orderHash] = false;

        emit OrderCreated(orderHash, abi.encodePacked(msg.sender, _triggerPrice, _expirationTimestamp, uint8(_orderType)));
    }

    ///@notice Cancels an Order
    ///@param _orderHash order hash/ID
    function cancelOrder(bytes32 _orderHash) external override nonReentrant(){
        Structs.Order memory _order = order[_orderHash];
        if(!_order.isAccountOwner()) revert Errors.InvalidOperator();
        if(_orderFulfilled(_orderHash)) revert Errors.OrderAlreadyFulfilled();
        //can only cancel open orders
        if(!_isOpenOrder(_orderHash)) revert Errors.NotOpenOrder();

        //delete order;
        delete order[_orderHash];

        emit OrderCancelled(_orderHash);
    }

    ///@notice Executes an open order
    ///@param _orderHash order hash/ID
    function fulfillOrder(bytes32 _orderHash) public override nonReentrant(){
        if(!canFulfillOrder(_orderHash)) revert Errors.CannotFulfillOrder();
        Structs.Order memory _order = order[_orderHash];

        _order.fulfillOrder(clearingHouse);
        orderFulfilled[_orderHash] = true;

        emit OrderFulfilled(_orderHash);
    }

    ///@notice Set new management fee
    ///@param _fee new fee amount
    function setManagementFee(uint256 _fee) external onlyOwner(){
        managementFee = _fee;
        emit SetManagementFee(_fee);
    }

    ///@notice Checks if an Order can be executed
    ///@return bool 
    function canFulfillOrder(bytes32 _orderHash) public view override returns(bool){
        return order[_orderHash].canFulfillOrder(clearingHouse) && !_orderFulfilled(_orderHash);
    }

    function hasEnoughAllowances(bytes32[] memory _orders) external view override returns(bool[] memory result){
        uint256 orderLen = _orders.length;
        for(uint i=0; i < orderLen; i++){
            Structs.Order memory _order = order[_orders[i]];
            result[i] = _order.hasEnoughAllowance(clearingHouse);
        }
    }

    //checks if Order is valid
    function _validOrder(
        uint64 expirationTimestamp, 
        bytes32  _orderHash
    ) internal view {
        // cannot have two open orders  with same ID
        if(_isOpenOrder(_orderHash)) revert Errors.OrderAlreadyExists();
        // ensure - expiration timestamp == 0 (no expiry) or not lt current timestamp
        if(expirationTimestamp > 0 && expirationTimestamp < block.timestamp)
            revert Errors.InvalidExpiration();
    }

    function _orderFulfilled(bytes32 _orderHash) internal view returns(bool){
        return orderFulfilled[_orderHash];
    }

    function _isOpenOrder(bytes32 _orderHash) internal view returns(bool){
        return order[_orderHash].position.quoteAssetAmount.toUint() > 0
                && !_orderFulfilled(_orderHash);
    }

    function _getOrderHash(IAmm _amm, Structs.OrderType _orderType, address _account) internal pure returns(bytes32){
        return keccak256(
            abi.encodePacked(
                _amm, 
                _orderType, 
                _account
            )
        );
    }

    function _transferFee() internal {
        if(managementFee > 0){
            if(msg.value != managementFee) revert Errors.IncorrectFee();
            (bool sent,) = feeManager.call{value: msg.value}("");
            if(!sent) revert Errors.TransferFailed();
        }
    }

}
