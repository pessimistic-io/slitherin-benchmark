//SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

abstract contract RouterEvent {
    event OnlyReceive(address _receiver, address _token, uint256 _amount);

    event CrossSwap(address _receiver, address _from, address _to, uint256 _fromAmount, uint256 _toAmount);

    event SendSingleCrossChain(address _receiver, address _token, uint256 _amount);

    event TransferRefund(address _receiver, address _token, uint256 _amount);
    
    event TransferFallback(address _receiver, address _token, uint256 _amount);
}

