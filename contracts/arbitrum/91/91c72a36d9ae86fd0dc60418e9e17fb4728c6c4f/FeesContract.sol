//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";

contract VoltaFees is Ownable {
    
	uint public compoundFees;
	uint public depositFees;
	uint public withdrawFees;
	uint public repaymentFees;

    uint private constant PRECISION = 1e6;

    constructor(uint compoundFees_, uint depositFees_, uint withdrawFees_, uint repaymentFees_) {
		compoundFees = compoundFees_;
        depositFees = depositFees_;
        withdrawFees = withdrawFees_;
        repaymentFees = repaymentFees_;
    }

    function getDepositFees(address /*_user*/) external view returns(uint) {
        return depositFees;
    }

    function getWithdrawFees(address /*_user*/) external view returns(uint) {
        return withdrawFees;
    }

    function getCompoundFees() external view returns(uint) {
        return compoundFees;
    }

    function getRepaymentFees(address /*_user*/) external view returns(uint) {
        return repaymentFees;
    }

    function updateFees(uint compoundFees_, uint depositFees_, uint withdrawFees_, uint repaymentFees_) external onlyOwner{
		compoundFees = compoundFees_;
        depositFees = depositFees_;
        withdrawFees = withdrawFees_;
        repaymentFees = repaymentFees_;
    }
}

