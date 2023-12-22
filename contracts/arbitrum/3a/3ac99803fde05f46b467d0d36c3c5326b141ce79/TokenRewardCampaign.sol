// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./TransferHelper.sol";
import "./EIP712.sol";

import "./console.sol";


contract TokenRewardCampaign is Ownable, ReentrancyGuard, EIP712 {
    using ECDSA for bytes32;
    using SafeMath for uint256;

    enum CampaignType { FCFS, Raffle }
    CampaignType public campaignType;

    address governer;
    address creator;

    // State variables
    ERC20 public rewardToken;
    bool public started;
    bool public finished;
    uint256 public totalParticipants;

    mapping(address => bool) public hasClaimedRaffleReward;

    uint256 public rewardSeats;

    // For FCFS
    uint256 public rewardPerUser;

    // For Raffle
    address[] public participants;
    mapping(address => bool) public isParticipant;
    address[] public winners;

    // Events
    event CampaignStarted();
    event CampaignFinished();
    event UserParticipated(address user);
    event RewardClaimed(address user, uint256 amount);
    
    struct ParticipationData {
        address user;
    }
    bytes32 internal constant TYPEHASH = keccak256("ParticipationData(address user)");

    modifier onlyRaffle {
        require(campaignType == CampaignType.Raffle, "Not a raffle campaign");
        _;
    }

    modifier onlyAdmins {
        require(msg.sender == owner() || msg.sender == governer, "Not admins");
        _;
    }

    modifier whenStarted {
        require(started, "Campaign not started");
        _;
    }

    modifier whenNotStarted {
        require(!started, "Campaign already started");
        _;
    }

    constructor(address _owner, address _rewardToken, uint256 _amount, uint256 _rewardSeats, CampaignType _campaignType, address _governer, address _creator)
        EIP712("TokenRewardCampaign", "1") 
    {
        transferOwnership(_owner);

        rewardToken = ERC20(_rewardToken);
        rewardPerUser = _amount.div(_rewardSeats);
        rewardSeats = _rewardSeats;
        started = false;
        finished = false;
        campaignType = _campaignType;
        governer = _governer;
        creator = _creator;
    }

    // Function to start a campaign
    function startCampaign() public onlyOwner whenNotStarted {
        started = true;

        emit CampaignStarted();
    }

    // Function to stop the campaign
    function stopCampaign() public onlyOwner whenStarted {
        started = false;
    }

    // Function to resume the campaign
    function resumeCampaign() public onlyOwner whenNotStarted {
        started = true;
    }

    // Function to withdraw funds by the owner
    function withdrawFunds() public onlyOwner whenNotStarted nonReentrant {
        uint256 balance = rewardToken.balanceOf(address(this));
        require(balance > 0, "No funds to withdraw");

        rewardToken.transfer(owner(), balance);
    }

    // Function to participate in a campaign
    function participate(ParticipationData calldata data, bytes calldata signature) public whenStarted nonReentrant {
        require(!finished, "Campaign finished");
        require(!isParticipant[msg.sender], "Already participated");
        require(verifySignature(data, signature), "Invalid signature"); 
        
        totalParticipants += 1;
        participants.push(msg.sender);
        isParticipant[msg.sender] = true;

        emit UserParticipated(msg.sender);

        // If it's FCFS, distribute reward immediately
        if (campaignType == CampaignType.FCFS) {
            require(rewardToken.balanceOf(address(this)) >= rewardPerUser, "Not enough rewards left");

            rewardToken.transfer(msg.sender, rewardPerUser);
            emit RewardClaimed(msg.sender, rewardPerUser);

            // Check if all rewards are distributed
            if (rewardToken.balanceOf(address(this)) < rewardPerUser) {
                finished = true;
                emit CampaignFinished();
            }
        }
    }

    function verifySignature(ParticipationData calldata _data, bytes calldata _signature) public view returns (bool) {
        bytes32 digest = _hashTypedDataV4(keccak256(abi.encode(
            TYPEHASH,
            _data.user
        )));

        return creator == digest.recover(_signature) && _data.user == msg.sender;
    }


    // Function to finish a raffle campaign
    function finishRaffleCampaign() public onlyAdmins {
        require(!finished, "Campaign already finished");
        finished = true;

        // Pick the winners
        for (uint i = 0; i < rewardSeats; i++) {
            if (participants.length > 0) {
                uint256 randomIndex = pseudoRandomNumber(participants.length);
                winners.push(participants[randomIndex]);

                // Remove the winner from the participants array to prevent them from being picked again
                participants[randomIndex] = participants[participants.length - 1];
                participants.pop();
            }
        }

        emit CampaignFinished();
    }

    function pseudoRandomNumber(uint256 _range) public view returns (uint256) {
        bytes32 hash = keccak256(abi.encodePacked(block.timestamp, block.difficulty));
        uint256 random = uint256(hash) % _range;
        return random;
    }

    // Function to claim reward for Raffle
    function claimRaffleReward() public nonReentrant returns (bool won) {
        require(finished, "Campaign not finished");
        require(isParticipant[msg.sender], "Not a participant");
        require(!hasClaimedRaffleReward[msg.sender], "Reward already claimed");

        uint256 rewardBalance = rewardToken.balanceOf(address(this));
        require(rewardBalance >= rewardPerUser, "Not enough rewards left");
        
        hasClaimedRaffleReward[msg.sender] = true;
        won = false;

        // Check if the user is a winner
        for (uint i = 0; i < winners.length; i++) {
            if (winners[i] == msg.sender) {
                rewardToken.transfer(msg.sender, rewardPerUser);
                emit RewardClaimed(msg.sender, rewardPerUser);

                won = true;
                break;
            }
        }
    }

    function getParticipants() external view returns (address[] memory) {
        return participants;
    }  

    function getWinners() external view returns (address[] memory) {
        return winners;
    } 
}

