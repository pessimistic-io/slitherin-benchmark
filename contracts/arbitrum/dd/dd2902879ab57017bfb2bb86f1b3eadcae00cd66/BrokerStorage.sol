// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./Admin.sol";

abstract contract BrokerStorage is Admin {

    address public implementation;

    struct Bet {
        address asset;
        address client;
        int256 volume;
    }

    // user => pool => symbolId => client address
    mapping (address => mapping (address => mapping (bytes32 => Bet))) public bets;

}

