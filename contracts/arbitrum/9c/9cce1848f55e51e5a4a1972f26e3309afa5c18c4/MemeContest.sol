// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

contract MemeContest {
    IERC20 private chivaToken;

    constructor(uint256 _reward, uint256 _contestDuration, address _chivaTokenAddress) {
        owner = msg.sender;
        reward = _reward;
        contestDuration = _contestDuration;
        contestStartTime = block.timestamp;
        lastWinnerIndex = 0;
        lastWinnerTimestamp = block.timestamp;
        contestCycle = 1;
        chivaToken = IERC20(_chivaTokenAddress);
    }

    struct Meme {
        address creator;
        string url;
        uint256 score;
    }

    Meme[] public memes;
    address public owner;
    uint256 public reward;
    uint256 public contestStartTime;
    uint256 public contestDuration;
    uint256 public lastWinnerIndex;
    uint256 public lastWinnerTimestamp;
    uint256 public contestCycle;

    function submitMeme(string memory _url) public {
        require(block.timestamp < contestStartTime + contestDuration, "Contest has ended");
        memes.push(Meme(msg.sender, _url, 0));
        assignScore();
    }

    function assignScore() private {
        uint256 score = getRandomScore();
        memes[memes.length - 1].score = score;

        if ((memes.length - lastWinnerIndex) % 7 == 0) {
            if (score < 77) {
                memes[memes.length - 1].score = 77;
            }
        }
    }

    function getRandomScore() private view returns (uint256) {
    bytes32 blockHash = blockhash(block.number - 1);
    uint256 seed = uint256(keccak256(abi.encodePacked(block.timestamp, blockHash, msg.sender)));
    return seed % 100;
    }


    function distributeRewards() public {
        require(block.timestamp >= lastWinnerTimestamp + contestDuration, "Not enough time has passed since last winner");

        address[] memory winners;
        uint256 highestScore = 0;

        for (uint256 i = lastWinnerIndex; i < memes.length; i++) {
            if (memes[i].score > highestScore) {
                highestScore = memes[i].score;
                delete winners;
                winners = new address[](1);
                winners[0] = memes[i].creator;
            } else if (memes[i].score == highestScore) {
                address[] memory newWinners = new address[](winners.length + 1);
                for (uint256 j = 0; j < winners.length; j++) {
                    newWinners[j] = winners[j];
                }
                newWinners[newWinners.length - 1] = memes[i].creator;
                winners = newWinners;
            }
        }

        uint256 rewardPerWinner = reward / winners.length;
        for (uint256 i = 0; i < winners.length; i++) {
            require(chivaToken.transferFrom(address(this), winners[i], rewardPerWinner), "Transfer failed");
        }

        lastWinnerIndex = memes.length;
        lastWinnerTimestamp = block.timestamp;
        contestCycle++;
    }

    modifier onlyOwner() {
    require(msg.sender == owner, "Only owner can call this function");
    _;
    }

    function setReward(uint256 _reward) public onlyOwner {
    require(block.timestamp >= lastWinnerTimestamp + contestDuration, "Not enough time has passed since last winner");
    reward = _reward;
    }


    function withdrawTokens() public {
        require(msg.sender == owner, "Only owner can withdraw tokens");
        require(block.timestamp >= lastWinnerTimestamp + contestDuration, "Not enough time has passed since last winner");

        uint256 tokensToWithdraw = reward * contestCycle;
        reward = 0;
        payable(owner).transfer(tokensToWithdraw);
    }
}

