// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";

contract GasPrice is Ownable {
    uint public maxGasPrice = 5000000000; // 5 gwei

    event NewMaxGasPrice(uint oldPrice, uint newPrice);

    function setMaxGasPrice(uint _maxGasPrice) external onlyOwner {
        emit NewMaxGasPrice(maxGasPrice, _maxGasPrice);
        maxGasPrice = _maxGasPrice;
    }
}

