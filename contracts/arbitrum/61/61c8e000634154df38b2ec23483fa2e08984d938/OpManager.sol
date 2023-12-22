// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./EnumerableSet.sol";

contract OpManager is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    event SetOperator(address op);
    event PauseOperator(address op, bool status);

    EnumerableSet.AddressSet private operators;
    mapping(address => bool) paused;
    bool flag;

    function init() external {
        require(!flag, "BYDEFI: already initialized!");
        super.initialize();
        flag = true;
    }

    function setOperator(address _op) external onlyOwner {
        operators.add(_op);
        emit SetOperator(_op);
    }

    function pauseOperator(address _op, bool _status) external onlyOwner {
        require(operators.contains(_op), "BYDEFI: invalid operator!");
        paused[_op] = _status;
        emit PauseOperator(_op, _status);
    }

    function isRunning(address _op) external view returns (bool) {
        require(operators.contains(_op), "BYDEFI: invalid operator!");
        return !paused[_op];
    }

    function getOperators() external view returns (address[] memory) {
        return operators.values();
    }

    function useless() public pure returns (uint256 a, string memory s) {
        a = 100;
        s = "hello world!";
    }
}

