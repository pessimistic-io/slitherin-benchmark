// SPDX-License-Identifier: AGPL

pragma solidity ^0.8.13;

import "./MerkleProof.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

/**
 * @title Private Contribution Vault
 * @notice Receive and log contributions from presale investors
 * @author BowTiedOriole
 */

contract PrivateContribution is ReentrancyGuard, Ownable {
    /* ========== STATE VARIABLES ========== */

    bytes32 public merkleRoot;

    struct Contribution {
        address contributer;
        uint256 amount;
        uint256 timestamp;
    }

    uint256 public totalContributions;
    uint256 public minContribution = 10 ether;
    uint256 public maxContributions = 250 ether;
    uint256 public startTime;
    uint256 public endTime;
    mapping(address => uint256) public userToContributionTotal;
    mapping(address => uint256) public userToNumberOfContributions;
    Contribution[] public contributions;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _owner, uint256 _startTime, uint256 _endTime) {
        require(_owner != address(0), "Zero address");
        require(_startTime > block.timestamp && _endTime > _startTime, "Timing");
        _transferOwnership(_owner);
        startTime = _startTime;
        endTime = _endTime;
    }

    /* ========== VIEWS ========== */

    function getContributionsByUser(address _user) external view returns (Contribution[] memory) {
        uint256 contributionsLength = contributions.length;
        Contribution[] memory results = new Contribution[](userToNumberOfContributions[_user]);

        uint256 resCount;
        for (uint256 i; i < contributionsLength; ++i) {
            if (contributions[i].contributer == _user) {
                results[resCount] = contributions[i];
                resCount++;
            }
        }
        return results;
    }

    function getAllContributions() external view returns (Contribution[] memory) {
        return contributions;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function contribute(bytes32[] calldata _proof) external payable nonReentrant {
        require(block.timestamp >= startTime && block.timestamp < endTime, "Not currently accepting contributions");
        require(msg.value >= minContribution, "Amount");
        require(msg.value + totalContributions <= maxContributions, "Exceeds max contributions");
        require(merkleRoot != 0, "Merkle root not initiated");

        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(_proof, merkleRoot, leaf), "Proof");

        userToNumberOfContributions[msg.sender]++;
        userToContributionTotal[msg.sender] += msg.value;
        totalContributions += msg.value;
        contributions.push(Contribution(msg.sender, msg.value, block.timestamp));

        emit Contributed(msg.sender, msg.value);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setMerkleRoot(bytes32 _newRoot) external onlyOwner {
        emit NewMerkleRoot(merkleRoot, _newRoot);
        merkleRoot = _newRoot;
    }

    function setMinContribution(uint256 _minContribution) external onlyOwner {
        emit NewMinContribution(minContribution, _minContribution);
        minContribution = _minContribution;
    }

    function setMaxContributions(uint256 _maxContributions) external onlyOwner {
        emit NewMaxContributions(maxContributions, _maxContributions);
        maxContributions = _maxContributions;
    }

    function setStartTime(uint256 _startTime) external onlyOwner {
        require(block.timestamp < startTime && _startTime > block.timestamp && _startTime < endTime, "Timing");
        emit NewStartTime(startTime, _startTime);
        startTime = _startTime;
    }

    function setEndTime(uint256 _endTime) external onlyOwner {
        require(block.timestamp < endTime && _endTime > block.timestamp && _endTime > startTime, "Timing");
        emit NewEndTime(endTime, _endTime);
        endTime = _endTime;
    }

    function withdraw() external onlyOwner {
        uint256 bal = address(this).balance;
        payable(msg.sender).transfer(bal);
        emit Withdrawn(msg.sender, bal);
    }

    /* ========== EVENTS ========== */

    event Contributed(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event NewMerkleRoot(bytes32 oldRoot, bytes32 newRoot);
    event NewMinContribution(uint256 oldMin, uint256 newMin);
    event NewMaxContributions(uint256 oldMax, uint256 newMax);
    event NewStartTime(uint256 oldStartTime, uint256 newStartTime);
    event NewEndTime(uint256 oldEndTime, uint256 newEndTime);
}

