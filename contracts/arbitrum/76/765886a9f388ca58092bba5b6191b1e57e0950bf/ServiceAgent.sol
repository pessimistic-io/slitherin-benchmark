// SPDX-License-Identifier: MIT
// ENVELOP(NIFTSY) Subscription Registry Contract V2


/// The subscription platform operates with the following role model 
/// (it is assumed that the actor with the role is implemented as a contract).
/// `Service Provider` is a contract whose services are sold by subscription.
/// `Agent` - a contract that sells a subscription on behalf ofservice provider. 
///  May receive sales commission
///  `Platform` - SubscriptionRegistry contract that performs processingsubscriptions, 
///  fares, tickets


pragma solidity 0.8.19;

import "./SafeERC20.sol";
import {Ticket} from "./SubscriptionRegistry.sol";
import "./IServiceProvider.sol";

/// @title ServiceAgent abstract contract 
/// @author Envelop project Team
/// @notice Abstract contract implements service agent logic.
/// For use with SubscriptionRegestry
/// @dev Use this code in service agent
/// for tickets selling
abstract contract ServiceAgent{
    using SafeERC20 for IERC20;

	
    receive() external payable {}
    function buySubscription(
        address _service,
        uint256 _tarifIndex,
        uint256 _payWithIndex,
        address _buyFor,
        address _payer
    ) public payable returns(Ticket memory ticket)
    {
        if (msg.value > 0){
            require(_payer == msg.sender, 'Only msg.sender can be payer');
        }
        // get service provider
        IServiceProvider sP = IServiceProvider(_service);
        
        // call SubscriptionRegistry that registered on current
        // service provider
        //return ISubscriptionRegistry(sP.subscriptionRegistry).buySubscription(
        ticket = sP.subscriptionRegistry().buySubscription{value: msg.value}(
            _service,
            _tarifIndex,
            _payWithIndex,
            _buyFor,
            _payer
        );

    }

    function _withdrawEther(address _feeReceiver) internal  {
        address payable o = payable(_feeReceiver);
        o.transfer(address(this).balance);
    }

    function _withdrawTokens(address _erc20, address _feeReceiver) internal  {
        IERC20(_erc20).safeTransfer(_feeReceiver, IERC20(_erc20).balanceOf(address(this)));
    }
}
