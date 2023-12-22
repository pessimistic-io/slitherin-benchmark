// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./DataTypes.sol";
import "./SafeERC20.sol";

contract ServiceAgreement {
    using SafeERC20 for IERC20;

    address public owner;
    uint256 lastUpdate;
    uint256 constant TWENTY_EIGHT_DAYS = 28 days;    
    DataTypes.SAParams public agreement;

    event ServiceAgreementCreated(DataTypes.SAParams params);

    modifier onlyAdmin() {
        require(msg.sender == owner, "Only the contract owner can call this function");
        _;
    } 

    constructor(address _admin, DataTypes.SAParams memory _agreement) {
        owner = _admin;
        agreement = _agreement;
        lastUpdate = block.timestamp;
    }

    function updateServiceAgreement(DataTypes.SAParams calldata _newAgreement) external onlyAdmin {
        require(block.timestamp > lastUpdate + TWENTY_EIGHT_DAYS, "Service agreement can only be updated once every 28 days");
        lastUpdate = block.timestamp;
        agreement = _newAgreement;
    }

    function agreementParams() external view returns (DataTypes.SAParams memory) {
        return agreement;
    }

    function bountyAmount() external view returns (uint256) {
        return agreement.bountyAmount;
    }

    function requestPaymentAmount() external view returns (uint256) {
        return agreement.requestPaymentAmount;
    }

    function requestExpirationTime() external view returns (uint256) {
        return agreement.requestExpirationTime;
    }

    function responseDataType() external view returns (string memory) {
        return agreement.responseDataType;
    }

    function endAt() external view returns (uint256) {
        return agreement.endAt;
    }

    function competitionContractAddress() external view returns (address) {
        return agreement.competitionContractAddress;
    }

    function stakedToken() external view returns (IERC20) {
        return IERC20(agreement.stakedToken);
    }

    function stakedAmount() external view returns (uint256) {
        return agreement.stakedAmount;
    }

    function disputeStake() external view returns (uint256) {
        return agreement.disputeStake;
    }

    function slashAmount() external view returns (uint256) {
        return agreement.slashAmount;
    }
}
