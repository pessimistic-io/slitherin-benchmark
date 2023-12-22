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

    IClearingHouse public constant clearingHouse = IClearingHouse(0x24D9D8767385805334ebd35243Dc809d0763b891);

    // Execute open order
    function executeOrder(Structs.Order memory orderStruct) internal {
        (Structs.OrderType orderType, address account,) = getOrderDetails(orderStruct);

        Decimal.decimal memory quoteAssetAmount = orderStruct.position.quoteAssetAmount;
        Decimal.decimal memory slippage = orderStruct.position.slippage;
        IAmm _amm = orderStruct.position.amm;
        
        if(orderType == Structs.OrderType.BUY_SLO || orderType == Structs.OrderType.SELL_SLO){
            // calculate current notional amount of user's position
            // - if notional amount gt initial quoteAsset amount set partially close position
            // - else close entire positon
            Decimal.decimal memory positionNotional = getPositionNotional(_amm, account);
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

    function _approveToCH(IERC20 _token, uint256 _amount) internal {
        _token.approve(address(clearingHouse), _amount);
    }

    function isAccountOwner(Structs.Order memory orderStruct) public view returns(bool){
        (, address account ,) = getOrderDetails(orderStruct);
        return msg.sender == account;
    }

    function canExecuteOrder(Structs.Order memory orderStruct) public view returns(bool){
        (Structs.OrderType orderType, address account , uint64 expiry) = getOrderDetails(orderStruct);
        // should be markprice
        uint256 _markPrice = orderStruct.position.amm.getMarkPrice().toUint();
        // order has not expired
        bool _ts = expiry == 0 || block.timestamp < expiry;
        // price trigger is met
        bool _pr;
        // account has allowance
        bool _ha;
        // order contract is delegate
        bool isDelegate;
        // position size
        int256 positionSize = getPositionSize(orderStruct.position.amm, account);
        //how to check if a position is open?
        bool _op = positionSize != 0;

        if(orderType == Structs.OrderType.BUY_SLO || orderType == Structs.OrderType.SELL_SLO){
            isDelegate = clearingHouse.delegateApproval().canClosePositionFor(account, address(this));
            _ha = hasEnoughBalanceAndApproval(
                orderStruct.position.amm,
                getPositionNotional(orderStruct.position.amm, account),
                0,
                positionSize > 0 ? IClearingHouse.Side.SELL : IClearingHouse.Side.BUY,
                false,
                account
            );
            _pr = orderType == Structs.OrderType.BUY_SLO 
                    ? _markPrice >= orderStruct.trigger
                    : _markPrice <= orderStruct.trigger;
        } else {
            isDelegate = clearingHouse.delegateApproval().canOpenPositionFor(account, address(this));
            _ha = hasEnoughBalanceAndApproval(
                orderStruct.position.amm,
                orderStruct.position.quoteAssetAmount.mulD(orderStruct.position.leverage),
                orderStruct.position.quoteAssetAmount.toUint(),
                 orderType == Structs.OrderType.BUY_LO ? IClearingHouse.Side.BUY : IClearingHouse.Side.SELL,
                true,
                account
            );
            _op = true;
            _pr = orderType == Structs.OrderType.BUY_LO 
                    ? _markPrice <= orderStruct.trigger
                    : _markPrice >= orderStruct.trigger;
        }

        return _ts && _pr && _op && _ha && isDelegate;
    }


    function hasEnoughBalanceAndApproval(
        IAmm _amm, 
        Decimal.decimal memory _positionNotional,
        uint256 _qAssetAmt,
        IClearingHouse.Side _side, 
        bool _isOpenPos, 
        address account
    ) internal view returns(bool){
        uint256 fees = calculateFees(
            _amm, 
            _positionNotional,
            _side, 
            _isOpenPos
        ).toUint();
        uint256 balance = getAccountBalance(_amm.quoteAsset(), account);
        uint256 chApproval = getAllowanceCH(_amm.quoteAsset(), account);
        return balance >= _qAssetAmt + fees  && chApproval >= _qAssetAmt + fees;
    }


    ///@dev Get user's position size
    function getPositionSize(IAmm amm, address account) public view returns(int256){
         return clearingHouse.getPosition(amm, account).size.toInt();
    }

    ///@dev Get User's positon notional amount
    function getPositionNotional(IAmm amm, address account) public view returns(Decimal.decimal memory){
         return clearingHouse.getPosition(amm, account).openNotional;
    }
    function getPositionMargin(IAmm amm, address account) public view returns(Decimal.decimal memory){
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
    function getAllowanceCH(IERC20 token, address account) internal view returns(uint256){
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
