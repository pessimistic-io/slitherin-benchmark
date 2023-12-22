pragma solidity ^0.8.0;

import "./RentalPaymentRecord.sol";

contract RentalPaymentAgreement {
    address public landlord;
    address public tenant;
    uint256 public startTime;
    uint256 public length;
    uint256 public totalAmount;
    uint256 public amountPerBill;
    uint256 public maxOverdueAmount;
    uint256 public penaltyAmount;
    uint256 public amountToAccept;
    uint256 public totalPaidAmount;
    bool public agreementAccepted = false;
    bool public ownerTerminated = false;
    bool public tenantTerminated = false;
    RentalPaymentRecord public paymentRecord;


    event PaymentReceived(uint256 amount, uint256 timestamp);

    // the agreement sets a maximum overdue amount (threshold), every exceeded amount will incur a penalty

    constructor(
        address _landlord,
        address _tenant,
        uint256 _startTime,
        uint256 _length,
        uint256 _totalAmount,
        uint256 _amountPerBill,
        uint256 _penaltyAmount,
        uint256 _amountToAccept,
        address _paymentRecord
    ) {

        require(_amountPerBill <= _totalAmount, "Amount per bill cannot be greater than total amount");
        require(_amountToAccept <= _totalAmount, "Amount to accept agreement cannot be greater than total amount");

        landlord = _landlord;
        tenant = _tenant;
        startTime = _startTime;
        length = _length;
        totalAmount = _totalAmount;
        penaltyAmount = _penaltyAmount;
        amountToAccept = _amountToAccept;
        paymentRecord = RentalPaymentRecord(_paymentRecord);
    }

    function acceptAgreement() external payable {
        require(msg.sender == tenant, "Only tenant can accept the agreement");
        require(block.timestamp < startTime, "Cannot accept after start time");

        if(amountToAccept > 0) {
            require(msg.value == amountToAccept, "Incorrect amount to accept agreement");
        }

        agreementAccepted = true;
    }

    function payRent() external payable {
        require(agreementAccepted, "Agreement not accepted");
        uint256 amountOverdue = getAmountOverdue();

        if(amountOverdue > 0) {
            require(msg.value >= amountOverdue, "Amount paid is less than overdue amount");
            payable(landlord).transfer(amountOverdue);
            payable(tenant).transfer(msg.value - amountOverdue);
        } else {
            require(msg.value == amountPerBill, "Incorrect amount to pay rent");
            payable(landlord).transfer(msg.value);
        } 

        // TODO: record payments behaviour in a unified PaymentRecord contract
        // paymentRecord.recordPayment(tenant, isGoodPayment);
        totalPaidAmount += msg.value;

        emit PaymentReceived(msg.value, block.timestamp);
    }

    function withdrawRentalPayment() external {
        require(msg.sender == landlord, "Only landlord can withdraw rent");
        payable(landlord).transfer(address(this).balance);
    }

    function transferLandlordship(address newLandlord) external {
        require(msg.sender == landlord, "Only landlord can transfer ownership");
        landlord = newLandlord;
    }

    function getAmountPerSecond() public view returns (uint256) {
        return totalAmount / length;
    }

    function getPaidSeconds() public view returns (uint256) {
        uint256 amountPerSecond = getAmountPerSecond();
        return totalPaidAmount / amountPerSecond;
    }

    function getPaidUntil() public view returns (uint256) {
        uint256 paidSeconds = getPaidSeconds();
        return startTime + paidSeconds;
    }

    function getAmountOverdue() public view returns (uint256) {
        uint256 paidUntil = getPaidUntil();
        if (block.timestamp > paidUntil) {
            uint256 overdueSeconds = block.timestamp - paidUntil;
            uint256 amountPerSecond = getAmountPerSecond();
            return overdueSeconds * amountPerSecond;
        } else {
            return 0;
        }
    }
}
