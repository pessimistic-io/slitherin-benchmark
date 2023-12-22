pragma solidity ^0.8.0;

import "./Ownable2Step.sol";
import "./RentalPaymentRecord.sol";
import "./RentalPaymentAgreement.sol";

contract RentalAgreementFactory is Ownable2Step {
    RentalPaymentRecord public paymentRecord;
    address[] public agreements;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => address[]) private landlordAgreements;

    constructor(address _paymentRecord) {
        paymentRecord = RentalPaymentRecord(_paymentRecord);
    }

    function createRentalAgreement(
        address tenant,
        uint256 startTime,
        uint256 length,
        uint256 totalAmount,
        uint256 amountPerBill,
        uint256 penaltyAmount,
        uint256 amountToAccept
    ) external returns (address) {
        RentalPaymentAgreement agreement = new RentalPaymentAgreement(
            msg.sender,
            tenant,
            startTime,
            length,
            totalAmount,
            amountPerBill,
            penaltyAmount,
            amountToAccept,
            address(paymentRecord)
        );
        agreements.push(address(agreement));

        // Add the new agreement to the list of authorized contracts in the payment record
        paymentRecord.addAuthorizedContract(address(agreement));

        
        balanceOf[msg.sender]++;
        landlordAgreements[msg.sender].push(address(agreement));
        
        return address(agreement);
    }

    function getAgreements() external view returns (address[] memory) {
        return agreements;
    }
    
    function contractByIndex(address landlord, uint256 index) external view returns (address) {
        require(index < balanceOf[landlord], "Index out of bounds");
        return landlordAgreements[landlord][index];
    }
}

