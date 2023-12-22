pragma solidity ^0.8.12;

import "./DataTypes.sol";
import "./IServiceAgreement.sol";
import "./ICompetition.sol";
import "./SafeERC20.sol";

library ModelerLibrary {

    using SafeERC20 for IERC20;

    event ValidatorOptedIn(address indexed validator);
    event ValidatorOptedOut(address indexed validator, uint256 optOutTime);
    event ModelerOptedIn(address indexed modeler);
    event ModelerOptedOut(address indexed modeler, uint256 optOutTime);
    event ValidatorRegistered(address indexed validator);

    uint256 constant ONE_DAY = 1 days;

    function registerValidator(address[] storage validatorAddresses, uint256 MAX_VALIDATORS, IERC20 validatorToken, DataTypes.ValidatorData storage validator, uint256 validatorStakeAmount, mapping(address => bool) storage isValRegistered) external {
        require(validatorAddresses.length < MAX_VALIDATORS, "Max validators reached");
        require(isValRegistered[msg.sender] == false || (validator.optOutTime > 0 && validator.optOutTime < block.timestamp - ONE_DAY) , "Validator already registered"); 
        validatorToken.safeTransferFrom(msg.sender, address(this), validatorStakeAmount);
        isValRegistered[msg.sender] = true;
        validator.currentStake = validatorStakeAmount;
        validator.optOutTime = ~uint256(0);
        validatorAddresses.push(msg.sender);
        emit ValidatorRegistered(msg.sender);
    }

    function removeValidatorRewardList(address _validator, address[] storage validatorAddresses) internal {
        for (uint256 i = 0; i < validatorAddresses.length; i++) {
            if (validatorAddresses[i] == _validator) {
                validatorAddresses[i] = validatorAddresses[validatorAddresses.length - 1];
                validatorAddresses.pop();
                return;
            }
        }
        revert("Address not found");
    }

    function optOutModeler(DataTypes.ModelerData storage modeler, ICompetition competitionContract) external {
        
        require(modeler.modelerSubmissionBlock != 0, "Modeler not registered");
        require(modeler.optOutTime > block.timestamp, "Modeler already opted out");
        require(modeler.optOutTime > block.timestamp + ONE_DAY, "Modeler opt out process already begun");
        modeler.optOutTime = block.timestamp + ONE_DAY; //modeler must be online for the next 24 hours or they may be slashed
        uint256 modelerStakedAmount = modeler.currentStake;
        modeler.currentStake = 0;
        IERC20(IServiceAgreement(competitionContract.getServiceAgreement()).stakedToken()).safeTransfer(msg.sender, modelerStakedAmount);
        
        emit ModelerOptedOut(msg.sender, modeler.optOutTime);
    }

    function optInModeler(DataTypes.ModelerData storage modeler, uint256 stakedAmount) external {
        require(modeler.modelerSubmissionBlock != 0, "Modeler not registered");
        require(modeler.currentStake >= stakedAmount, "Modeler does not have enough stake");
        modeler.optOutTime = ~uint256(0); //maxint
        emit ModelerOptedIn(msg.sender);
    }

    function optInValidator(DataTypes.ValidatorData storage validator, uint256 validatorStakeAmount, address[] storage validatorAddresses, mapping(address => bool) storage isValRegistered) external {
        require(isValRegistered[msg.sender], "Validator not registered");
        require(validator.currentStake >= validatorStakeAmount, "Not have enough stake");
        validatorAddresses.push(msg.sender);
        validator.optOutTime = ~uint256(0); //maxint
        emit ValidatorOptedIn(msg.sender);
    }

    function optOutValidator(DataTypes.ValidatorData storage validator, address[] storage validatorAddresses, address competitionContract, mapping(address => bool) storage isValRegistered) external {
        require(isValRegistered[msg.sender], "Validator not registered");
        require(validator.optOutTime > block.timestamp, "Validator already opted out");
        require(validator.optOutTime > block.timestamp + ONE_DAY, "Validator opt out process already begun");

        validator.optOutTime = block.timestamp + ONE_DAY; //validator must be online for the next 24 hours or they may be slashed
        uint256 validatorStakedAmount = validator.currentStake;
        validator.currentStake = 0;
        removeValidatorRewardList(msg.sender, validatorAddresses);
        IERC20(IServiceAgreement(ICompetition(competitionContract).getServiceAgreement()).stakedToken()).safeTransfer(msg.sender, validatorStakedAmount);
        emit ValidatorOptedOut(msg.sender, validator.optOutTime);
    }

    function emergencyOptOutValidator(address validatorAddress, DataTypes.ValidatorData storage validatorData, address[] storage validatorAddresses, mapping(address => bool) storage isValRegistered) external {
        require(isValRegistered[validatorAddress], "Validator not registered");
        validatorData.optOutTime = block.timestamp;
        removeValidatorRewardList(validatorAddress, validatorAddresses);
        emit ValidatorOptedOut(validatorAddress, validatorData.optOutTime);
    }
} 
