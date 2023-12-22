// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

contract EthBalance {
    function check(address addy) public view returns(uint256) {
        return addy.balance;
    }
}