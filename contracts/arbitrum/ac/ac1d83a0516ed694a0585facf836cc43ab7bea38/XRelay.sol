// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.16;

import {Ownable} from "./Ownable.sol";
import {Address} from "./Address.sol";

contract XRelay is Ownable {
    function execute(address target_, bytes calldata data_) external onlyOwner {
        (address feeCollector, uint256 feeAmount) = abi.decode(data_[data_.length - 64:], (address, uint256));
        uint256 balanceBefore = feeCollector.balance;
        Address.functionCall(target_, data_);
        require(feeCollector.balance - balanceBefore >= feeAmount, "XR: insufficient fee payment");
    }
}

