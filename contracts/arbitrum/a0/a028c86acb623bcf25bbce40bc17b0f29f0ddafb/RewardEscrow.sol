// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./Initializable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";

contract RewardEscrow is Initializable, ReentrancyGuardUpgradeable {

    address payable private topContributor;
    address private operator;

    event RewardReceived(uint256 value);
    event TopContributorSet(address topContributor);
    event OperatorSet(address operator);
    event RewardSent(address topContributor, uint256 rewardValue);

    error TopContributorNotSet();
    error RewardFailedToSend(address, uint256);
    error UnAuthorizedOperator();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    receive() external payable {
        emit RewardReceived(msg.value);
    }

    modifier onlyOperator() {
        if (msg.sender != getOperator()) {
            revert UnAuthorizedOperator();
        }
        _;
    }

    function initialize(address _operator) public payable initializer {
        operator = _operator;
        emit OperatorSet(_operator);
    }

    function sendReward() external nonReentrant {
        if(topContributor == address(0)) {
            revert TopContributorNotSet();
        }
        // TODO: Check if topContributor implements the "receiveGroupMintReward"
        uint256 rewardValue = address(this).balance;
        (bool success, ) = topContributor.call{value: rewardValue}("");
        if (!success) {
            revert RewardFailedToSend(topContributor, rewardValue);
        }
        emit RewardSent(topContributor, rewardValue);
    }

    function setTopContributor(address payable _topContributor) external onlyOperator {
        topContributor = _topContributor;
        emit TopContributorSet(topContributor);
    }
    
    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
        emit OperatorSet(_operator);
    }

    function getTopContributor() public view returns (address) {
        return topContributor;
    }

    function getOperator() public view returns (address) {
        return operator;
    }
}
