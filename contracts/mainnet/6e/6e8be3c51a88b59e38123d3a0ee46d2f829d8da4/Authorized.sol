// SPDX-License-Identifier: MIT

/// Authorized V 0.1.0 (made by @aurealarcon aurelianoa.eth)

pragma solidity ^0.8.17;

import { Ownable } from "./Ownable.sol";

contract Authorized is Ownable {

    /// @notice Generic error when a user attempts to access a feature/function without proper access
    error Unauthorized();

    /// @notice Event emitted when a new operator is added
    event SetOperator(address indexed operator);

    /// @notice A mapping of the authorized delegate operators
    /// @dev operator address => authorized status
    mapping (address => bool) private authorizedOperators;
    

    /// @dev Modifier to ensure caller is authorized operator
    modifier onlyAuthorizedOperator() {
        if (!authorizedOperators[msg.sender]) {
            revert Unauthorized();
        }
        _;
    }

    /// @notice Add an authorized Operator
    /// @param _operator address of the operator
    /// @param status status of the operator
    function setAuthorizedOperator(address _operator, bool status) public virtual onlyOwner {
        /// check if address is not null
        require(_operator != address(0), "Authorized System: Operator address cannot be null");
        
        /// update the operator status
        authorizedOperators[_operator] = status;
        emit SetOperator(_operator);
    }

    /// @notice Get the status of an operator
    /// @param _operator address of the operator
    /// @return status of the operator
    function getAuthorizedOperator(address _operator) external view virtual returns (bool) {
        return authorizedOperators[_operator];
    }
}
