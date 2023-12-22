// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPetroBank {
    function buy(uint256 paymentAmount_) external returns (bool);
    function sell(uint256 sellAmount_) external returns (bool) ;
    function getOutput(
        address _tokenIn,
        uint256 _amount
    ) external returns (uint256);
    function sellAndSendToAddress(uint256 sellAmount_, address _to) external returns (bool);
    function buyAndSendToAddress(uint256 paymentAmount_, address _to) external returns (bool);
}

