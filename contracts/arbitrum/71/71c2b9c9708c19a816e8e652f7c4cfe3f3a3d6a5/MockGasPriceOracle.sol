// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import {Ownable} from "./Ownable.sol";

contract MockGasPriceOracle is Ownable {
    uint256 public gasPrice;

    constructor(uint256 _gasPrice) {
        gasPrice = _gasPrice;
    }

    function setGasPrice(uint256 _newGasPrice) external onlyOwner {
        gasPrice = _newGasPrice;
    }

    function latestAnswer() external view returns (int256) {
        return int256(gasPrice);
    }
}

