// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

contract StoreTest {

    uint256 number;
    function storeVal(uint256 num) public {
        number = num;
    }
}