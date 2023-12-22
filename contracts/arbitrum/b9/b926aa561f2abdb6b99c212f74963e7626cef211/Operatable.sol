// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Owned} from "./Owned.sol";

contract Operatable is Owned {
    event LogOperatorChanged(address indexed, bool);
    error ErrNotAllowedOperator();

    mapping(address => bool) public operators;

    constructor(address _owner) Owned(_owner) {}

    modifier onlyOperators() {
        if (!operators[msg.sender] && msg.sender != owner) {
            revert ErrNotAllowedOperator();
        }
        _;
    }

    function setOperator(address operator, bool status) external onlyOwner {
        operators[operator] = status;
        emit LogOperatorChanged(operator, status);
    }
}

