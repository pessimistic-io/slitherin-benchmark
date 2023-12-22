// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./Ownable.sol";
import "./School.sol";
import "./SmolBrain.sol";

contract Rocket is Ownable {
    uint256 public deadline;

    School public school;
    SmolBrain public smolBrain;

    mapping(uint256 => uint256) public timestampJoined;

    event Board(uint256 smolBrainTokenId, uint256 timestamp);
    event DeadlineSet(uint256 deadline);
    event SchoolSet(address school);
    event SmolBrainSet(address smolBrain);

    constructor() {
        deadline = block.timestamp + 3 days;
    }

    function board() external {
        uint256 _balance = smolBrain.balanceOf(msg.sender);

        require(_balance > 0, "Rocket: no smols to board");

        for (uint256 _index = 0; _index < _balance; _index++) {
            uint256 _tokenId = smolBrain.tokenOfOwnerByIndex(
                msg.sender,
                _index
            );

            if (school.isAtSchool(_tokenId)) {
                timestampJoined[_tokenId] = block.timestamp;

                emit Board(_tokenId, block.timestamp);
            }
        }
    }

    function boardedBeforeDeadline(uint256 _tokenId)
        public
        view
        returns (bool)
    {
        require(timestampJoined[_tokenId] > 0, "Rocket: smol not boarded");

        return timestampJoined[_tokenId] <= deadline;
    }

    // ADMIN

    function setDeadline(uint256 _deadline) external onlyOwner {
        deadline = _deadline;

        emit DeadlineSet(_deadline);
    }

    function setSchool(address _school) external onlyOwner {
        school = School(_school);

        emit SchoolSet(_school);
    }

    function setSmolBrain(address _smolBrain) external onlyOwner {
        smolBrain = SmolBrain(_smolBrain);

        emit SmolBrainSet(_smolBrain);
    }
}

