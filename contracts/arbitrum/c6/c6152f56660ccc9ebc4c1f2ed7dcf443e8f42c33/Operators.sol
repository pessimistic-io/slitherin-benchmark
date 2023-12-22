// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./SafeERC20.sol";
import "./Ownable.sol";

contract Operators is Ownable {
    mapping(address => bool) public operators;

    event OperatorUpdated(address indexed operator, bool indexed status);

    modifier onlyOperator() {
        require(operators[msg.sender], "Operator: caller is not the operator");
        _;
    }

    // Update the status of the operator
    function updateOperator(address _operator, bool _status) external onlyOwner {
        operators[_operator] = _status;
        emit OperatorUpdated(_operator, _status);
    }
}

