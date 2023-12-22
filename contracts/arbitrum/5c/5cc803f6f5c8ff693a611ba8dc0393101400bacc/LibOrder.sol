// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import { IERC20 } from "./IERC20.sol";
import "./IAmm.sol";
import "./IClearingHouse.sol";
import "./INFTPerpOrder.sol";
import "./Decimal.sol";
import "./SignedDecimal.sol";
import "./Structs.sol";

library LibOrder {
    using Decimal for Decimal.decimal;
    using SignedDecimal for SignedDecimal.signedDecimal;

    struct CanExec {
        // is expired
        bool ts;
        // is price trigger met
        bool pr;
        // is account's position delegated and does account have enough allowance
        bool ha;
        // is position open
        bool op;
    }

    // Execute open order
    function fulfillOrder(Structs.Order memory orderStruct, IClearingHouse clearingHouse) internal {
        (Structs.OrderType orderType, address account,) = getOrderDetails(orderStruct);

        Decimal.decimal memory quoteAssetAmount = orderStruct.position.quoteAssetAmount;
        Decimal.decimal memory slippage = orderStruct.position.slippage;
        IAmm _amm = orderStruct.position.amm;
        
        if(orderType == Structs.OrderType.BUY_SLO || orderType == Structs.OrderType.SELL_SLO){
            // calculate current notional amount of user's position
            // - if notional amount gt initial quoteAsset amount set partially close position
            // - else close entire positon
            Decimal.decimal memory positionNotional = getPositionNotional(_amm, account, clearingHouse);
            if(positionNotional.d > quoteAssetAmount.d){
                // partially close position
                clearingHouse.partialCloseFor(
                    _amm, 
                    quoteAssetAmount.divD(positionNotional), 
                    slippage, 
                    account
                );
            } else {
                // fully close position
                clearingHouse.closePositionFor(
                    _amm, 
                    slippage, 
                    account
                );
            } 
        } else {
            IClearingHouse.Side side = orderType == Structs.OrderType.BUY_LO ? IClearingHouse.Side.BUY : IClearingHouse.Side.SELL;
            // execute Limit Order(open position)
            clearingHouse.openPositionFor(
                _amm, 
                side, 
                quoteAssetAmount, 
                orderStruct.position.leverage, 
                slippage, 
                account
            );
        }
    }

    function isAccountOwner(Structs.Order memory orderStruct) public view returns(bool){
        (, address account ,) = getOrderDetails(orderStruct);
        return msg.sender == account;
    }

    function canFulfillOrder(Structs.Order memory orderStruct, IClearingHouse clearingHouse) public view returns(bool){
        (Structs.OrderType orderType, address account , uint64 expiry) = getOrderDetails(orderStruct);
        CanExec memory canExec;
        // should be markprice
        uint256 _markPrice = orderStruct.position.amm.getMarkPrice().toUint();
        // order has not expired
        canExec.ts = expiry == 0 || block.timestamp < expiry;
        // position size
        int256 positionSize = getPositionSize(orderStruct.position.amm, account, clearingHouse);
        //how to check if a position is open?
        canExec.op = positionSize != 0;

        canExec.ha = hasEnoughAllowance(
                orderStruct,
                clearingHouse
            );

        if(orderType == Structs.OrderType.BUY_SLO || orderType == Structs.OrderType.SELL_SLO){
            canExec.pr = orderType == Structs.OrderType.BUY_SLO 
                    ? _markPrice >= orderStruct.trigger
                    : _markPrice <= orderStruct.trigger;
        } else {
            canExec.op = true;
            canExec.pr = orderType == Structs.OrderType.BUY_LO 
                    ? _markPrice <= orderStruct.trigger
                    : _markPrice >= orderStruct.trigger;
        }

        return canExec.ts && canExec.pr && canExec.op && canExec.ha;
    }

    function hasEnoughAllowance(
        Structs.Order memory orderStruct,
        IClearingHouse clearingHouse
    ) internal view returns(bool){
        (Structs.OrderType orderType, address account, ) = getOrderDetails(orderStruct);

        bool isSLO = orderType == Structs.OrderType.BUY_SLO || orderType == Structs.OrderType.SELL_SLO ? true : false;

        // is position delegated
        bool isd = isSLO ? clearingHouse.delegateApproval().canClosePositionFor(account, address(this))
                         : clearingHouse.delegateApproval().canClosePositionFor(account, address(this)); 

        IClearingHouse.Side _side;
        if(isSLO){
            if(getPositionSize(orderStruct.position.amm, account, clearingHouse) > 0){
                _side = IClearingHouse.Side.SELL;
            } else {
                _side = IClearingHouse.Side.BUY;
            }
        } else {
            if(orderType == Structs.OrderType.BUY_LO){
                _side = IClearingHouse.Side.BUY;
            } else {
                _side = IClearingHouse.Side.SELL;
            }
        }

        uint256 fees = calculateFees(
            orderStruct.position.amm, 
            isSLO ? getPositionNotional(orderStruct.position.amm, account, clearingHouse)
                  : orderStruct.position.quoteAssetAmount.mulD(orderStruct.position.leverage),
            _side, 
            isSLO ? false : true
        ).toUint();

        uint256 _qAssetAmt = isSLO ? 0 : orderStruct.position.quoteAssetAmount.toUint();
        
        uint256 balance = getAccountBalance(orderStruct.position.amm.quoteAsset(), account);
        uint256 chApproval = getAllowanceCH(orderStruct.position.amm.quoteAsset(), account, clearingHouse);
        return balance >= _qAssetAmt + fees  && chApproval >= _qAssetAmt + fees && isd;
    }


    ///@dev Get user's position size
    function getPositionSize(IAmm amm, address account, IClearingHouse clearingHouse) public view returns(int256){
         return clearingHouse.getPosition(amm, account).size.toInt();
    }

    ///@dev Get User's positon notional amount
    function getPositionNotional(IAmm amm, address account, IClearingHouse clearingHouse) public view returns(Decimal.decimal memory){
         return clearingHouse.getPosition(amm, account).openNotional;
    }

    function getPositionMargin(IAmm amm, address account, IClearingHouse clearingHouse) public view returns(Decimal.decimal memory){
        return clearingHouse.getPosition(amm, account).margin;
    }
    
    ///@dev Get Order Info/Details
    function getOrderDetails(
        Structs.Order memory orderStruct
    ) public pure returns(Structs.OrderType, address, uint64){
        //Todo: make more efficient
        return (
            Structs.OrderType(uint8(orderStruct.detail >> 248)),
            address(uint160(orderStruct.detail << 32 >> 96)),
            uint64(orderStruct.detail << 192 >> 192)
        );  
    }

    function getAllowanceCH(IERC20 token, address account, IClearingHouse clearingHouse) internal view returns(uint256){
        return token.allowance(account, address(clearingHouse));
    }

    function getAccountBalance(IERC20 token, address account) internal view returns(uint256){
        return token.balanceOf(account);
    }

    function calculateFees(
        IAmm _amm,
        Decimal.decimal memory _positionNotional,
        IClearingHouse.Side _side,
        bool _isOpenPos
    ) internal view returns (Decimal.decimal memory fees) {
        fees = _amm.calcFee(
            _side == IClearingHouse.Side.BUY ? IAmm.Dir.ADD_TO_AMM : IAmm.Dir.REMOVE_FROM_AMM,
            _positionNotional,
            _isOpenPos
        );
    }

}
