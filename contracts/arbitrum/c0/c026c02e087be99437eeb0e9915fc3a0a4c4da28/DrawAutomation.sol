// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./AutomationCompatible.sol";
import "./IBids.sol";

contract DrawAutomation is AutomationCompatibleInterface {
    mapping(address => mapping(uint256 => uint256)) public rafflesDrawTime;

    function checkUpkeep(
        bytes calldata checkData
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        (address bids) = abi.decode(
            checkData,
            (address)
        );

        uint256 currentRaffleId = IBids(bids).getCurrentRaffleId();
        uint256 drawTime = getRaffleDrawTime(bids, currentRaffleId);
        if (drawTime == 0) {
            upkeepNeeded = IBids(bids).isAvailableToDraw(currentRaffleId);
            performData = abi.encode(bids, currentRaffleId);
        } else {
            upkeepNeeded = drawTime <= block.timestamp;
            performData = abi.encode(bids, currentRaffleId);
        }
    }

    function performUpkeep(bytes calldata performData) external {
        (address bids, uint256 raffleId) = abi.decode(
            performData,
            (address, uint256)
        );
        uint256 drawTime = getRaffleDrawTime(bids, raffleId);
        if (drawTime == 0) {
            // save draw time
            rafflesDrawTime[bids][raffleId] = block.timestamp + 3600;
        } else {
            IBids(bids).draw(raffleId);
        }
    }

    function getRaffleDrawTime(address bids, uint256 raffleId) public view returns (uint256) {
        return rafflesDrawTime[bids][raffleId];
    }
}

