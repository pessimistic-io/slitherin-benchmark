pragma solidity ^0.8.0;

import "./Ownable2Step.sol";

contract RentalPaymentRecord is Ownable2Step {
    mapping(address => uint256) public goodPayments;
    mapping(address => uint256) public latePayments;
    mapping(address => uint256) public missedPayments;
    mapping(address => bool) private authorizedContracts;
    mapping(address => bool) private authorizedFactory;

    modifier onlyAuthorizedContracts() {
        require(
            authorizedContracts[msg.sender],
            "Caller is not an authorized contract"
        );
        _;
    }

    modifier onlyAuthorizedFactory() {
        require(
            authorizedFactory[msg.sender],
            "Caller is not an authorized factory"
        );
        _;
    }

    function addAuthorizedContract(address contractAddress) external onlyAuthorizedFactory {
        authorizedContracts[contractAddress] = true;
    }

    function recordPayment(address tenant, bool isOnTime, uint256 count) external onlyAuthorizedContracts {
        if (!isOnTime) {
            latePayments[tenant] += count;
        } else {
            goodPayments[tenant] += count;
        }
    }

    function setAuthorizedFactory(address _factoryAddress, bool _isAuthorized) external onlyOwner {
        authorizedFactory[_factoryAddress] = _isAuthorized;
    }
}
