// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;

import "./NFTPerpOrder.sol";
import "./NFTPerpOrder.sol";
import "./IResolver.sol";
import "./OpsReady.sol";

contract NFTPerpOrderResolver is OpsReady, IResolver {
    NFTPerpOrder public immutable _NFTPerpOrder_;

    constructor(address _nftPerpOrder, address _ops) OpsReady(_ops){
        _NFTPerpOrder_ = NFTPerpOrder(_nftPerpOrder);
    }

    //https://docs.gelato.network/developer-products/gelato-ops-smart-contract-automation-hub/methods-for-submitting-your-task/smart-contract
    function startTask() external {
        IOps(ops).createTask(
            address(_NFTPerpOrder_), 
            _NFTPerpOrder_.executeOrder.selector,
            address(this),
            abi.encodeWithSelector(this.checker.selector)
        );
    }
    
    //https://docs.gelato.network/developer-products/gelato-ops-smart-contract-automation-hub/guides/writing-a-resolver/smart-contract-resolver#checking-multiple-functions-in-one-resolver
    function checker() external view returns (bool canExec, bytes memory execPayload) {
        bytes32[] memory _openOrders = _NFTPerpOrder_.getOpenOrders();
        uint256 _openOrderLen = _openOrders.length;
        for (uint256 i = 0; i < _openOrderLen; i++) {

            canExec = _NFTPerpOrder_.canExecuteOrder(_openOrders[i]);

            execPayload = abi.encodeWithSelector(
                _NFTPerpOrder_.executeOrder.selector,
                _openOrders[i]
            );

            if (canExec) break;
        }
    }
}
