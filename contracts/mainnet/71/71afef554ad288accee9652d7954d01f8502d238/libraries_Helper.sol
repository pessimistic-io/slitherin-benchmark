// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./libraries_Helper.sol";

contract $Helper {
    constructor() {}

    function $safeTransferNative(address _to,uint256 _value) external {
        return Helper.safeTransferNative(_to,_value);
    }
}

