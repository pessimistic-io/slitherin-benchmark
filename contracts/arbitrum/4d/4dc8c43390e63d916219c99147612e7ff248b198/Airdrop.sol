// SPDX-License-Identifier: AGPL

pragma solidity ^0.8.13;

import "./IPrivateContribution.sol";
import "./Ownable.sol";
import "./IERC20.sol";

/**
 * @title   Airdrop
 * @notice  Loads contribution information from PrivateContribution & selects random winner
 * @dev     There is no Chainlink VRF on Arbitrum. Will need to pass randomization seed when calling airdrop
 * @author  HessianX
 * @custom:developer BowTiedOriole
 */

contract Airdrop is Ownable {
    // ----- Events -----

    event Winner(address _winner);

    // ----- State Variables -----

    /// @notice Address of the PrivateContribution contract
    IPrivateContribution public immutable privateContribution;

    /// @notice Winner of the raffle
    address public winner;

    // ----- Construction -----

    /// @notice Sets the address of PrivateContribution contract
    /// @param  _privateContribution    Address of PrivateContribution contract
    constructor(address _privateContribution) {
        privateContribution = IPrivateContribution(_privateContribution);
    }

    // ----- State Changing -----

    /// @notice Runs the raffle and selects winner
    /// @dev    Can only be called by the owner and only once
    /// @param  _seed   Randomization seed
    function airdrop(uint256 _seed) external onlyOwner {
        require(winner == address(0), "raffle completed");
        uint256 endSale = privateContribution.endTime();
        require(block.timestamp > endSale, "!ready");

        StructContribution.Contribution[] memory contributions = privateContribution.getAllContributions();
        uint256 length = contributions.length;

        // Count number of contributions & contribution total in last 24 hours of private sale
        uint256 lastDayContributionTotal;
        uint256 entries;
        uint256 start = endSale - (24 * 3600);

        while (length > 0) {
            if (contributions[length - 1].timestamp >= start) {
                lastDayContributionTotal += contributions[length - 1].amount;
                entries++;
                length--;
            } else {
                // Since contributions are in order of timestamp, don't have to loop through all
                break;
            }
        }

        // Select winner
        require(entries > 0, "!entries");
        uint256 rand = uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, block.number, _seed))) % lastDayContributionTotal;
        for (uint256 i = contributions.length - entries; i < contributions.length; ++i) {
            if (rand < contributions[i].amount) {
                winner = contributions[i].contributer;
                emit Winner(winner);
                break;
            } else {
                rand -= contributions[i].amount;
            }
        }
    }
}

