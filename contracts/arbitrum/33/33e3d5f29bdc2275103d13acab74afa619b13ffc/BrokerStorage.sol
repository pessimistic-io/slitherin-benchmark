// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./Admin.sol";

abstract contract BrokerStorage is Admin {

    address public implementation;

    // user => pool => symbolId => client address
    mapping (address => mapping (address => mapping (bytes32 => address))) public clients;

}

