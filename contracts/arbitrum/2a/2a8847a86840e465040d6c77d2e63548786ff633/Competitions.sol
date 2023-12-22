pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IERC721.sol";
import "./SafeERC20.sol";
import "./Counters.sol";
import "./SafeMath.sol";

contract Competitions {
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    address public restrictedAddress;
    address public treasuryAddress;

    Counters.Counter private _competitionIds;

    struct Participant {
        address user;
        uint256 joinDate;
    }

    mapping(uint256 => Participant[]) public participants;
    mapping(uint256 => mapping(address => bool)) public hasJoined;
    mapping(uint256 => mapping(uint256 => address)) public winners;
    mapping(uint256 => uint256) public rewards;
    mapping(uint256 => mapping(uint256 => address)) public additionalRewardsAddresses;
    mapping(uint256 => mapping(address => uint256)) public additionalRewardsAmounts;
    mapping(uint256 => uint256) public participantCount;
    mapping(uint256 => uint256) public rewardCount;
    mapping(uint256 => uint256) public winnerCount;
    mapping(uint256 => uint256) public rewardDistribution;

    struct Competition {
        uint256 id;
        address owner;
        string name;
        uint256 entryFeeAmount;
        address entryFeeToken;
        uint256 endDate;
        string optionsJson;
        address restrictedAddress;
        address treasuryAddress;
        uint256 percentageForOwner;
        uint256 percentageForTreasury;
    }

    mapping(uint256 => Competition) public competitions;

    constructor(address _restrictedAddress, address _treasuryAddress) {
        restrictedAddress = _restrictedAddress;
        treasuryAddress = _treasuryAddress;
    }

    // Events
    // Event when a user joined competition
    event Joined(address user, uint256 competitionId, uint256 joinDate);

    // Event to notify when a competition is created
    event CompetitionCreated(
        uint256 id,
        address owner,
        string name,
        uint256 entryFeeAmount,
        address entryFeeToken,
        uint256 percentageForOwner,
        uint256 percentageForTreasury,
        uint256 endDate,
        string optionsJson
    );

    function createCompetition(
        string memory name,
        address owner,
        uint256 entryFeeAmount,
        address entryFeeToken,
        uint256 percentageForOwner,
        uint256 percentageForTreasury,
        uint256 endDate,
        string memory optionsJson
    ) external returns (uint256) {
        require(bytes(name).length <= 50, "Name too long");
        require(percentageForOwner <= 90, "Owner percentage too high");
        require(percentageForTreasury <= 10, "Treasury percentage too high");
        require(
            percentageForOwner + percentageForTreasury <= 100,
            "Total percentages must be less than or equal to 100%"
        );
        require(endDate > block.timestamp, "End date must be in the future");

        _competitionIds.increment();
        uint256 newCompetitionId = _competitionIds.current();

        competitions[newCompetitionId] = Competition(
            newCompetitionId,
            owner,
            name,
            entryFeeAmount,
            entryFeeToken,
            endDate,
            optionsJson,
            restrictedAddress,
            treasuryAddress,
            percentageForOwner,
            percentageForTreasury
        );

        // emit event
        emit CompetitionCreated(
            newCompetitionId,
            owner,
            name,
            entryFeeAmount,
            entryFeeToken,
            percentageForOwner,
            percentageForTreasury,
            endDate,
            optionsJson
        );

        return newCompetitionId;
    }

    function join(uint256 competitionId) external {
        Competition storage competition = competitions[competitionId];
        require(block.timestamp < competition.endDate, "Competition ended");
        require(!hasJoined[competitionId][msg.sender], "Already joined");

        if (competition.entryFeeAmount > 0) {
            uint256 balance = IERC20(competition.entryFeeToken).balanceOf(
                msg.sender
            );
            require(
                balance >= competition.entryFeeAmount,
                "Insufficient balance"
            );
            IERC20(competition.entryFeeToken).transferFrom(
                msg.sender,
                address(this),
                competition.entryFeeAmount
            );

            // Increase the rewards 
            rewards[competitionId] += competition.entryFeeAmount;
        }

        participants[competitionId].push(Participant(msg.sender, block.timestamp));
        hasJoined[competitionId][msg.sender] = true;

        emit Joined(msg.sender, competitionId, block.timestamp);
    }

    function invite(address player, uint256 competitionId) external {
        Competition storage competition = competitions[competitionId];

        // Require owner to invite
        require(msg.sender == competition.owner, "Not authorized");
        require(block.timestamp < competition.endDate, "Competition ended");
        require(!hasJoined[competitionId][player], "Already joined");

        participants[competitionId].push(Participant(player, block.timestamp));
        hasJoined[competitionId][player] = true;

        emit Joined(player, block.timestamp, competitionId);
    }

    function setWinners(
        address[] calldata _winners,
        uint256[] calldata rewardDistributionPercentages,
        uint256 competitionId
    ) external {
        Competition storage competition = competitions[competitionId];

        require(
            block.timestamp >= competition.endDate,
            "Competition not ended"
        );
        require(msg.sender == restrictedAddress, "Not authorized");

        require(
            _winners.length == rewardDistributionPercentages.length,
            "Invalid input"
        );

        // Validate reward distribution
        uint256 totalPercentage;
        for (uint256 i = 0; i < rewardDistributionPercentages.length; i++) {
            totalPercentage += rewardDistributionPercentages[i];
        }
        require(
            totalPercentage == 100,
            "Total reward distribution must equal 100%"
        );

        for (uint256 i = 0; i < _winners.length; i++) {
            require(
                hasJoined[competitionId][_winners[i]],
                "Winner not a participant"
            );
        }

        uint256 balance = rewards[competitionId];
        // owner amount is owner percentage of the total balance

        if (balance > 0) {
            uint256 ownerAmount = competition.percentageForOwner > 0
                ? (balance * competition.percentageForOwner) / 100
                : 0;
            uint256 treasuryAmount = competition.percentageForTreasury > 0
                ? (balance * competition.percentageForTreasury) / 100
                : 0;
            uint256 winnersAmount = balance - ownerAmount - treasuryAmount;

            for (uint256 i = 0; i < _winners.length; i++) {
                winners[competitionId][i] = _winners[i];
                uint256 winnerAmount = (winnersAmount *
                    rewardDistributionPercentages[i]) / 100;

                // Transfer fee rewards
                IERC20(competition.entryFeeToken).safeTransfer(
                    _winners[i],
                    winnerAmount
                );

                claimRewards(
                    _winners[i],
                    rewardDistributionPercentages[i],
                    competitionId
                );
            }
            // Transfer fee rewards

            IERC20(competition.entryFeeToken).safeTransfer(
                treasuryAddress,
                treasuryAmount
            );
            IERC20(competition.entryFeeToken).safeTransfer(
                competition.owner,
                ownerAmount
            );
        } else {
            for (uint256 i = 0; i < _winners.length; i++) {
                winners[competitionId][i] = _winners[i];
                claimRewards(
                    _winners[i],
                    rewardDistributionPercentages[i],
                    competitionId
                );
            }
        }
    }

    function claimRewards(
        address winner,
        uint256 winnerPercentage,
        uint256 competitionId
    ) internal {
        Competition storage competition = competitions[competitionId];
        // Transfer additional rewards
        for (uint256 i = 0; i < rewardCount[competitionId]; i++) {
            address rewardAddress = additionalRewardsAddresses[competitionId][i];
            uint256 rewardAmount = additionalRewardsAmounts[competitionId][
                rewardAddress
            ];

            if (rewardAmount > 0) {
                uint256 winnerRewardShare = (rewardAmount * winnerPercentage) /
                    100;
                IERC20(rewardAddress).safeTransfer(winner, winnerRewardShare);
            }
        }
    }

    function addReward(
        address _rewardAddress,
        uint256 _amount,
        uint256 competitionId
    ) external {
        Competition storage competition = competitions[competitionId];
        require(msg.sender == competition.owner, "Not authorized");
        require(block.timestamp < competition.endDate, "Competition ended");
        require(_amount > 0, "Invalid amount");

        IERC20(_rewardAddress).transferFrom(msg.sender, address(this), _amount);

        // If it didn't exist, add it to the list
        if (additionalRewardsAmounts[competitionId][_rewardAddress] == 0) {
            additionalRewardsAddresses[competitionId][
                rewardCount[competitionId]
            ] = _rewardAddress;

            rewardCount[competitionId]++;
        }

        additionalRewardsAmounts[competitionId][_rewardAddress] += _amount;
    }

    // Function to see the total rewards accumulated (subtracting the amounts for owner and treasury)
    // only the ones from entry fees
    function getTotalRewards(
        uint256 competitionId
    ) external view returns (uint256) {
        Competition storage competition = competitions[competitionId];
        uint256 balance = rewards[competitionId];

        if (balance == 0) {
            return 0;
        }

        uint256 ownerAmount = competition.percentageForOwner > 0
            ? (balance * competition.percentageForOwner) / 100
            : 0;
        uint256 treasuryAmount = competition.percentageForTreasury > 0
            ? (balance * competition.percentageForTreasury) / 100
            : 0;
        return balance - ownerAmount - treasuryAmount;
    }

    // Returns the number of players that joined
    function getParticipantsCount(
        uint256 competitionId
    ) external view returns (uint256) {
        Competition storage competition = competitions[competitionId];
        return participants[competitionId].length;
    }

    // Function to withdraw ETH sent to this contract by mistake
    function withdrawETH() external {
        require(msg.sender == restrictedAddress, "Not authorized");
        payable(msg.sender).transfer(address(this).balance);
    }
}

