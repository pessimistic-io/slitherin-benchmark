// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./Admin.sol";

abstract contract SymbolManagerStorage is Admin {

    // admin will be truned in to Timelock after deployment

    event NewImplementation(address newImplementation);

    address public implementation;

    // symbolId => symbol
    mapping (bytes32 => address) public symbols;

    // indexed symbols for looping
    address[] public indexedSymbols;

    // pTokenId => active symbols array for specific pTokenId (with position)
    mapping (uint256 => address[]) public activeSymbols;

    // total initial margin required for all symbols
    int256 public initialMarginRequired;

}

