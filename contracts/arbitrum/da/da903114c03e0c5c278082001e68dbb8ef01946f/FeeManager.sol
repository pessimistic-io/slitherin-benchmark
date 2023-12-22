// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./IERC20.sol";

import "./IFeeManager.sol";

contract FeeManager is Ownable, IFeeManager {
    uint256 public override baseFee = 1e16; //0.01ether, todo: check the source cost of a game
    uint256 public override getFactor = 4;
    /// payment=>spender=>amount
    mapping(address => mapping(address => uint256)) public override allowance;
    uint256 public override totalBaseFee;

    receive() external payable {}

    function payBaseFee() public payable {
        require(msg.value == baseFee, "FEE_ERR");
        totalBaseFee += msg.value;
    }

    function withdraw(address payment, uint256 amount) public {
        require(allowance[payment][msg.sender] >= amount, "ERR_ALLOWANCE");
        allowance[payment][msg.sender] -= amount;
        if (payment == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(payment).transfer(msg.sender, amount);
        }
        emit Withdrawal(payment, msg.sender, amount);
    }

    function calcFee(uint256 amount) public view returns (uint256) {
        return (amount * getFactor) / 100;
    }

    /// dao
    function setBaseFee(uint256 amount) public onlyOwner {
        baseFee = amount;
    }

    function setFactor(uint256 factor) public onlyOwner {
        require(factor < 100, "ERR");
        getFactor = factor;
    }

    function addApprove(address payment, address spender, uint256 amount) public onlyOwner {
        allowance[payment][spender] += amount;
        emit ApproveAdded(payment, spender, amount);
    }

    function reduceApprove(address payment, address spender, uint256 amount) public onlyOwner {
        allowance[payment][spender] -= amount;
        emit ApproveReduced(payment, spender, amount);
    }

    function claimBaseFee() public onlyOwner {
        payable(msg.sender).transfer(totalBaseFee);
        totalBaseFee = 0;
    }
}

