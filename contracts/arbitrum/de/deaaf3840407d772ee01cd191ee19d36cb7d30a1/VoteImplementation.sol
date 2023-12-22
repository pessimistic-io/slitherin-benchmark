// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./VoteStorage.sol";

contract VoteImplementation is VoteStorage {

    event NewVoteTopic(string topic, uint256 numOptions, uint256 deadline);

    event NewVote(address indexed voter, uint256 option);

    uint256 public constant cooldownTime = 900;

    function initializeVote(string memory topic_, uint256 numOptions_, uint256 deadline_) external _onlyAdmin_ {
        require(block.timestamp > deadline, 'VoteImplementation.initializeVote: still in vote');
        topic = topic_;
        numOptions = numOptions_;
        deadline = deadline_;
        delete voters;
        emit NewVoteTopic(topic_, numOptions_, deadline_);
    }

    function vote(uint256 option) external {
        require(block.timestamp < deadline, 'VoteImplementation.vote: vote ended');
        require(option >= 1 && option <= numOptions, 'VoteImplementation.vote: invalid vote option');
        voters.push(msg.sender);
        votes[msg.sender] = option;
        if (block.timestamp + cooldownTime >= deadline) {
            deadline += cooldownTime;
        }
        emit NewVote(msg.sender, option);
    }

    //================================================================================
    // Convenient query functions
    //================================================================================

    function getVoters() external view returns (address[] memory) {
        return voters;
    }

    function getVotes(address[] memory accounts) external view returns (uint256[] memory) {
        uint256[] memory options = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            options[i] = votes[accounts[i]];
        }
        return options;
    }

}

