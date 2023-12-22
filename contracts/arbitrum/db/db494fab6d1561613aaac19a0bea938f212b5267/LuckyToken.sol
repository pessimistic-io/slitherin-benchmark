// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ReentrancyGuard.sol";
import "./ERC20.sol";
import "./Counters.sol";

contract LuckyToken is ERC20, ReentrancyGuard {

    using Counters for Counters.Counter;

    uint256 public constant ONE = 1 * (10 ** 18);
    uint256 public constant RATE = 1000000000 * ONE;
    uint256 public startTime;
    uint256 public nextDifficultyCount = 100;
    address public creator;

    mapping(address => bool) public hasClaimed;
    mapping(address => uint256) public lastClaim;
    Counters.Counter private nonceCounter;
    Counters.Counter private luckyCounter;
    Counters.Counter private difficultyCounter;

    event lucky(bytes32 hash, bytes32 difficulty);

    constructor() ERC20("Lucky Token", "Lucky") {
        difficultyCounter.increment();
        nonceCounter = Counters.Counter(block.timestamp);
        creator = msg.sender;
        _mint(msg.sender, 800 * RATE);
    }

    function setStartTime(uint256 _startTime) external {
        require(msg.sender == creator, "Only creator");
        require(startTime == 0, "Already set");
        startTime = _startTime;
    }

    function getLuckyCount() public view returns (uint256) {
        return luckyCounter.current();
    }

    function getDifficulty() public view returns (uint256) {
        return difficultyCounter.current();
    }

    function getNextDifficultyCount() public view returns (uint256) {
        return nextDifficultyCount;
    }

    function calculateHash() internal returns (bytes32) {
        uint256 nonce = nonceCounter.current();
        nonceCounter.increment();
        return keccak256(abi.encodePacked(msg.sender, nonce, block.timestamp, getLuckyCount(), getDifficulty()));
    }

    function proofOfLucky() internal returns (bool) {
        bytes32 hash = calculateHash();
        bytes32 _difficulty = bytes32(uint256(2) ** (256 - getDifficulty()) - 1);
        emit lucky(hash, _difficulty);
        return hash <= _difficulty;
    }

    function withdraw() external {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance");
        (bool success, ) = creator.call{value: balance}("");
        require(success, "Transfer failed.");
    }

    receive() external payable nonReentrant {
        require(block.timestamp >= startTime && startTime > 0, "Not started");
        require(msg.sender == tx.origin, "Only EOA");
        require(!hasClaimed[msg.sender], "You have already claimed");
        require(lastClaim[msg.sender] < block.timestamp - 10 seconds, "Only once every 10 seconds");
        require(getDifficulty() < 10, "claim limit reached");
        lastClaim[msg.sender] = block.timestamp;
        if (proofOfLucky()) {
            luckyCounter.increment();
            uint256 luckyCount = luckyCounter.current();
            if (luckyCount >= nextDifficultyCount) {
                difficultyCounter.increment();
                nextDifficultyCount = nextDifficultyCount * 2;
            }
            _mint(msg.sender, RATE);
            hasClaimed[msg.sender] = true;
        } else {
            _mint(msg.sender, 0);
        }
    }
}
