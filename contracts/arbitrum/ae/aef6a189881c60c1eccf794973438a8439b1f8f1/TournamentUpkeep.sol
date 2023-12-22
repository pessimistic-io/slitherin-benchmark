// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

// AutomationCompatible.sol imports the functions from both ./AutomationBase.sol and
// ./interfaces/AutomationCompatibleInterface.sol
import { AutomationCompatibleInterface } from "./AutomationCompatible.sol";
import { ITournamentConsumer } from "./ITournamentConsumer.sol";

/**
 * @notice Upkeep contract to perform automated tasks for Tournament
 */
contract TournamentUpkeep is AutomationCompatibleInterface {

    ITournamentConsumer consumer;
    address owner;
    address pendingOwner;

    constructor(ITournamentConsumer _consumer) {
        consumer = _consumer;
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "onlyOwner: sender is not owner");
        _;
    }

    // @dev transfer ownership
    function transferOwnership(address newOwner) external onlyOwner {
        pendingOwner = newOwner;
    }

    // @dev claim ownership
    function claimOwnership() external {
        require(msg.sender == pendingOwner, "claimOwnership: sender is not pending owner");
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    function setConsumer(address _consumer) public onlyOwner {
        consumer = ITournamentConsumer(_consumer);
    }

    function checkUpkeep(
        bytes calldata /* checkData */
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        upkeepNeeded = consumer.canUpdate();
    }

    function performUpkeep(bytes calldata /* performData */) external override {
        consumer.update();
    }
}

