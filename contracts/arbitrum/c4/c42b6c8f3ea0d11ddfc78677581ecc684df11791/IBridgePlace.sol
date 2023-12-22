// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface IBridgePlace {
    function send(
        address _token,
        uint256 _destinationChainId,
        address _destinationAddress,
        uint256 _amount,
        uint256 _minAmount,
        bool _isNative
    ) external payable;

}

