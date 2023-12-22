// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "./IERC20.sol";
import {Ownable} from "./Ownable.sol";

abstract contract Pool is Ownable {
    string private _name;
    mapping(address => bool) private operators;
    uint256 private _outBalance;
    address public withdrawer;

    constructor(string memory name_, address withdrawer_) {
        _name = name_;
        withdrawer = withdrawer_;
    }

    modifier onlyOperator() {
        require(operators[_msgSender()], "caller is not operator");
        _;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function outBalance() public view returns (uint256) {
        return _outBalance;
    }

    function emergencyWithdraw(IERC20 token, uint256 amount) external {
        require(msg.sender == withdrawer, "not withdrawer");
        token.transfer(msg.sender, amount);
    }

    function withdraw(IERC20 token, address receiver, uint256 amount) external onlyOperator {
        _outBalance += amount;
        token.transfer(receiver, amount);
    }

    function setOperator(address operator, bool state) external onlyOwner {
        operators[operator] = state;
    }

    function setWithdrawer(address withdrawer_) external onlyOwner {
        withdrawer = withdrawer_;
    }
}

