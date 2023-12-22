// SPDX-License-Identifier: MIT

pragma solidity ^0.8.14;

import "./DefaultRateProvider.sol";

/** 
 *  ankrETH rate provider contract.
 */
contract AnkrETHRateProvider is DefaultRateProvider {

    // --- Init ---
    constructor(address _token) DefaultRateProvider(_token) {}

    function ankrETH() external view returns(address) {
        return s_token;
    }
}
