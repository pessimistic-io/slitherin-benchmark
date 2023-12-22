// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

contract MockFailingFeeCollector {
    receive() external payable {
        revert();
    }
}

