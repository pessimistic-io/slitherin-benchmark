// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;


contract T {
    uint8 val;

    function get() public view returns (uint8) {
        return val;
    }

    function set(uint8 _newVal) public {
        val = _newVal;
    }
}