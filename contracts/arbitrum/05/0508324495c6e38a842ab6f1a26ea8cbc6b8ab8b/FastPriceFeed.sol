// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "./IFastPriceFeed.sol";
import "./BaseAccess.sol";

contract FastPriceFeed is IFastPriceFeed, BaseAccess {
    string public constant defaultDescription = "FastPriceFeed";
    string public description;

    uint256 public answer;
    uint256 public decimals;
    uint80 public roundId;

    mapping(uint80 => uint256) public answers;
    mapping(uint80 => uint256) public latestAts;

    event SetDecription(string description);
    event SetLatestAnswer(uint256 roundId, uint256 answer, uint256 currentTimestamp);

    constructor(string memory _description) {
        if (bytes(_description).length > 0) {
            _setDescription(_description);
        }
    }

    function setDescription(string memory _description) onlyOwner external {
        _setDescription(_description);
    }

    function _setDescription(string memory _description) internal {
        description = _description;
        emit SetDecription(_description);
    }

    function getDescription() external view returns (string memory) {
        return bytes(description).length == 0 ? defaultDescription : string.concat(description, ": ", defaultDescription);
    }

    function setLatestAnswer(uint256 _answer) limitAccess external {
        roundId += 1;
        answer = _answer;
        answers[roundId] = _answer;
        uint256 currentTimestamp = block.timestamp;
        latestAts[roundId] = currentTimestamp;
        emit SetLatestAnswer(roundId, _answer, currentTimestamp);
    }

    function latestAnswer() external view override returns (uint256) {
        return answer;
    }

    function latestRound() external view override returns (uint80) {
        return roundId;
    }

    function getRoundData(uint80 _roundId) external view override returns (uint80, uint256, uint256, uint256, uint80) {
        return (_roundId, answers[_roundId], latestAts[_roundId], 0, 0);
    }

    function latestSynchronizedPrice() external view override returns (uint256, uint256) {
        return (answers[roundId], latestAts[roundId]);
    }
}
