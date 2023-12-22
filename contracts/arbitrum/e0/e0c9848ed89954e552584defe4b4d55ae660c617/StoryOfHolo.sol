// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./ERC1155.sol";
import "./SGT.sol";

// Uncomment this line to use console.log
// import "hardhat/console.sol";

contract StoryOfHolo is Ownable, ERC1155{

    uint256 public s_ids_supply;

    uint256 public s_voting_supply;

    uint256 public s_active_voting_id;

    bool public isActiveVoting;

    SGT public mint_pass_token;

     /**
     * @notice Info about mint passs tokens used
     */
    mapping(uint256 => mapping(uint256 => bool)) public s_mintPassToStatus;

    mapping(uint256 => Voting) public s_idToVoting;

    mapping(uint => string) public s_idToTokenURI;

    mapping(uint256 => uint256) public s_badgeIdToVotingId;

    struct Voting{
        uint256 id;
        bool isActive;
        uint256 totalVotes;
        uint256 totalFirstVotes;
        uint256 totalSecondVotes;
        uint256 firstTokenId;
        uint256 secondTokenId;
        string firstTokenURI;
        string secondTokenURI;
        uint256 startTimestamp;
    }

    enum Vote{ForFirst, ForSecond}

 
    event Voted(address indexed voter, uint indexed votingId, Vote indexed vote);

    event Finished(uint256 votingId, uint256 timestamp);

    event VotingCreated(uint256 votingId, uint256 timestamp);

    constructor(address _mintPass)ERC1155("") payable {
       require(_mintPass != address(0), "Mint pass can't be zero");
       mint_pass_token = SGT(_mintPass);
    }
    
    /**
	 * Votes
	 * @notice only owner
	 */
    function vote(uint256 _passId, Vote _vote) external {
        require(mint_pass_token.ownerOf(_passId) == msg.sender, "Not the owner of token");
        require(isActiveVoting, "There is no active voting");

        Voting memory currentVoting = s_idToVoting[s_active_voting_id];

        require(!s_mintPassToStatus[currentVoting.id][_passId], "This token was already used for vote");
        currentVoting.totalVotes++;

        uint256 tokenId;
        
        if(_vote == Vote.ForFirst){
            currentVoting.totalFirstVotes++;
            tokenId = currentVoting.firstTokenId;
        }else{
            currentVoting.totalSecondVotes++;
            tokenId = currentVoting.secondTokenId;
        }

        _mint(msg.sender, tokenId, 1, "");
        
        s_mintPassToStatus[currentVoting.id][_passId] = true;
        s_idToVoting[currentVoting.id] = currentVoting;

        emit Voted(msg.sender, currentVoting.id, _vote);
        
    }

      /**
	 * Creates new voting 
	 * @notice only owner
	 */
	function createVoting(string memory _firstTokenURI, string memory _secondTokenURI) external onlyOwner {
        uint256 currentVotingId = s_voting_supply;
        uint256 currentIdSupply = s_ids_supply;
        
        require(!isActiveVoting, "There is already active voting");

         // create new Voting;

        Voting memory newVoting = Voting({
            id:currentVotingId,
            isActive:true,
            totalVotes:0,
            totalFirstVotes:0,
            totalSecondVotes:0,
            firstTokenId:currentIdSupply,
            secondTokenId:currentIdSupply + 1,
            firstTokenURI:_firstTokenURI,
            secondTokenURI:_secondTokenURI,
            startTimestamp:block.timestamp
        });
        
        // Set Active Voting ID
        s_active_voting_id = newVoting.id;
        
        // Set Voting Details
        s_idToVoting[s_voting_supply] = newVoting;
        
        // Set passId to corresponding VotingId
        s_badgeIdToVotingId[newVoting.firstTokenId] = newVoting.id;
        s_badgeIdToVotingId[newVoting.secondTokenId] = newVoting.id;

        // Set Voting Supply
        s_voting_supply++;

        // Set Ids Supply
        s_ids_supply+=2;

        isActiveVoting = true;
        
        // Set URIs for tokens
        s_idToTokenURI[newVoting.firstTokenId] = _firstTokenURI;
        s_idToTokenURI[newVoting.secondTokenId] = _secondTokenURI;

        emit VotingCreated(
           newVoting.id,
           block.timestamp
        );

	}

     /**
	 * Finishes current voting
	 * @notice only owner
	 */
	function finishVoting() external onlyOwner {
        uint256 currentVotingId = s_voting_supply;
	    Voting memory currentVoitng = s_idToVoting[currentVotingId];

        require(isActiveVoting, "Current voting is not active");

        currentVoitng.isActive = false;

        s_idToVoting[currentVotingId] = currentVoitng;

        isActiveVoting = false;

        emit Finished(currentVotingId, block.timestamp);
	}

    function setURI(uint _id, string memory _uri) external onlyOwner {
       s_idToTokenURI[_id] = _uri;
     }

     function uri(uint _id) public override view returns (string memory) {
        return s_idToTokenURI[_id];
     }


    /**
	 * Withdraw ETH from contract to owner address
	 * @notice only owner can withdraw
	 */
	function withdrawETH() external onlyOwner {
		(bool sent, ) = msg.sender.call{value: address(this).balance}('');
		require(sent, 'Failed to withdraw ETH');
	}

}

