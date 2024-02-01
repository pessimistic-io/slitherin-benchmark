// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.6.0;

import "./contracts-exposed_OSBFactory.sol";

contract $OSBFactory is OSBFactory {
    constructor() {}

    function $__Context_init() external {
        return super.__Context_init();
    }

    function $__Context_init_unchained() external {
        return super.__Context_init_unchained();
    }

    function $_msgSender() external view returns (address) {
        return super._msgSender();
    }

    function $_msgData() external view returns (bytes memory) {
        return super._msgData();
    }
}

