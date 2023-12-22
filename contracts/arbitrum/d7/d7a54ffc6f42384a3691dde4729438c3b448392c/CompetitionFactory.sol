pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IERC721.sol";
import "./SafeERC20.sol";
import "./Counters.sol";
import "./SafeMath.sol";

contract CompetitionFactory {
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;

    address public restrictedAddress;
    address public treasuryAddress;

    Counters.Counter private _competitionIds;

    mapping(uint256 => Competition) public competitions;

    constructor(address _restrictedAddress, address _treasuryAddress) {
        restrictedAddress = _restrictedAddress;
        treasuryAddress = _treasuryAddress;
    }

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

        competitions[newCompetitionId] = new Competition(
            newCompetitionId,
            owner,
            name,
            entryFeeAmount,
            entryFeeToken,
            percentageForOwner,
            percentageForTreasury,
            endDate,
            optionsJson,
            restrictedAddress,
            treasuryAddress
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
}

contract Competition {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    uint256 public id;
    address public owner;
    string public name;
    uint256 public entryFeeAmount;
    address public entryFeeToken;
    uint256 public endDate;
    string public optionsJson;
    address private restrictedAddress;
    address private treasuryAddress;
    uint256 public percentageForOwner;
    uint256 public percentageForTreasury;

    struct Participant {
        address user;
        uint256 joinDate;
    }

    Participant[] public participants;
    mapping(address => bool) public hasJoined;

    mapping(uint256 => address) public winners;

    // Address -> Amount (we should use a iterable map instead of this)
    mapping(uint256 => address) public additionalRewardsAddresses;
    mapping(address => uint256) public additionalRewardsAmounts;
    uint256 public rewardCount;

    uint256 public winnerCount;
    uint256[] public rewardDistribution;

    // Event when a user joined competition
    event Joined(address user, uint256 joinDate);

    // Update the constructor with the new parameters
    constructor(
        uint256 _id,
        address _owner,
        string memory _name,
        uint256 _entryFeeAmount,
        address _entryFeeToken,
        uint256 _percentageForOwner,
        uint256 _percentageForTreasury,
        uint256 _endDate,
        string memory _optionsJson,
        address _restrictedAddress,
        address _treasuryAddress
    ) {
        id = _id;
        owner = _owner;
        name = _name;
        entryFeeAmount = _entryFeeAmount;
        entryFeeToken = _entryFeeToken;
        endDate = _endDate;
        optionsJson = _optionsJson;
        restrictedAddress = _restrictedAddress;
        treasuryAddress = _treasuryAddress;
        percentageForOwner = _percentageForOwner;
        percentageForTreasury = _percentageForTreasury;
    }

    function join() external {
        require(block.timestamp < endDate, "Competition ended");
        require(!hasJoined[msg.sender], "Already joined");

   
        if (entryFeeAmount > 0) {
             uint256 balance = IERC20(entryFeeToken).balanceOf(msg.sender);
            require(balance >= entryFeeAmount, "Insufficient balance");
            IERC20(entryFeeToken).transferFrom(
                msg.sender,
                address(this),
                entryFeeAmount
            );
        }

        participants.push(Participant(msg.sender, block.timestamp));
        hasJoined[msg.sender] = true;

        emit Joined(msg.sender, block.timestamp);
    }

    function setWinners(
        address[] calldata _winners,
        uint256[] calldata rewardDistributionPercentages
    ) external {
        require(block.timestamp >= endDate, "Competition not ended");
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
            require(hasJoined[_winners[i]], "Winner not a participant");
        }

        uint256 balance = IERC20(entryFeeToken).balanceOf(address(this));
        // owner amount is owner percentage of the total balance

        if (balance > 0) {
            uint256 ownerAmount = percentageForOwner > 0
                ? (balance * percentageForOwner) / 100
                : 0;
            uint256 treasuryAmount = percentageForTreasury > 0
                ? (balance * percentageForTreasury) / 100
                : 0;
            uint256 winnersAmount = balance - ownerAmount - treasuryAmount;

            for (uint256 i = 0; i < _winners.length; i++) {
                winners[i] = _winners[i];
                uint256 winnerAmount = (winnersAmount *
                    rewardDistributionPercentages[i]) / 100;

                // Transfer fee rewards
                IERC20(entryFeeToken).safeTransfer(_winners[i], winnerAmount);

                claimRewards(_winners[i], rewardDistributionPercentages[i]);
            }
            // Transfer fee rewards

            IERC20(entryFeeToken).safeTransfer(treasuryAddress, treasuryAmount);
            IERC20(entryFeeToken).safeTransfer(owner, ownerAmount);
        } else {
            for (uint256 i = 0; i < _winners.length; i++) {
                winners[i] = _winners[i];
                claimRewards(_winners[i], rewardDistributionPercentages[i]);
            }
        }
    }

    function claimRewards(address winner, uint256 winnerPercentage) internal {
        // Transfer additional rewards
        for (uint256 i = 0; i < rewardCount; i++) {
            address rewardAddress = additionalRewardsAddresses[i];
            uint256 rewardAmount = additionalRewardsAmounts[rewardAddress];

            if (rewardAmount > 0) {
                uint256 winnerRewardShare = (rewardAmount * winnerPercentage) /
                    100;
                IERC20(rewardAddress).safeTransfer(winner, winnerRewardShare);
            }
        }
    }

    function addReward(address _rewardAddress, uint256 _amount) external {
        require(msg.sender == owner, "Not authorized");
        require(block.timestamp < endDate, "Competition ended");
        require(_amount > 0, "Invalid amount");

        IERC20(_rewardAddress).transferFrom(
            msg.sender,
            address(this),
            _amount
        );

        // If it didn't exist, add it to the list
        if (additionalRewardsAmounts[_rewardAddress] == 0) {
            additionalRewardsAddresses[rewardCount] = _rewardAddress;

            rewardCount++;
        }

        additionalRewardsAmounts[_rewardAddress] += _amount;
    }

    // Function to see the total rewards accumulated (subtracting the amounts for owner and treasury)
    // only the ones from entry fees
    function getTotalRewards() external view returns (uint256) {
        uint256 balance = IERC20(entryFeeToken).balanceOf(address(this));

        if (balance == 0) {
            return 0;
        }

        uint256 ownerAmount = percentageForOwner > 0
            ? (balance * percentageForOwner) / 100
            : 0;
        uint256 treasuryAmount = percentageForTreasury > 0
            ? (balance * percentageForTreasury) / 100
            : 0;
        return balance - ownerAmount - treasuryAmount;
    }
}

