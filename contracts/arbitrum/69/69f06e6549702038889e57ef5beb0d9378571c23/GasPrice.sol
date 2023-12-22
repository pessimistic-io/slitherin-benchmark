// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./Ownable.sol";

contract GasPrice is Ownable {
    uint256 public maxGasPrice = 10000000000; // 10 gwei

    event NewMaxGasPrice(uint256 oldPrice, uint256 newPrice);

    function setMaxGasPrice(uint256 _maxGasPrice) external onlyOwner {
        emit NewMaxGasPrice(maxGasPrice, _maxGasPrice);
        maxGasPrice = _maxGasPrice;
    }
}

