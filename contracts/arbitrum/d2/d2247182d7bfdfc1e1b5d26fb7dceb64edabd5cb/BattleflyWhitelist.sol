// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.2;

import "./OwnableUpgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./IBattleflyGame.sol";
import { MerkleProof } from "./MerkleProof.sol";

contract BattleflyWhitelist is OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;
    mapping(address => mapping(uint256 => uint256)) public hasClaimedSpecialNFT;
    mapping(address => mapping(uint256 => uint256)) public hasClaimedBattlefly;
    bytes32 public merkleRootBattlefly;
    bytes32 public merkleRootSpecialNFT;

    mapping(address => bool) private adminAccess;
    IBattleflyGame Game;
    uint256 StartTime;
    uint256 EndTime;

    event ClaimBattlefly(address indexed to, uint256 amount, uint256 indexed battleflyType);
    event ClaimSpecialNFT(address indexed to, uint256 amount, uint256 indexed specialNFTType);

    function initialize(address battleflyGameContractAddress) public initializer {
        __Ownable_init();
        Game = IBattleflyGame(battleflyGameContractAddress);
    }

    function setAdminAccess(address user, bool access) external onlyOwner {
        adminAccess[user] = access;
    }

    function setMerkleRootBattlefly(bytes32 merkleRoot) external onlyAdminAccess {
        merkleRootBattlefly = merkleRoot;
    }

    function setMerkleRootSpecialNFT(bytes32 merkleRoot) external onlyAdminAccess {
        merkleRootSpecialNFT = merkleRoot;
    }

    function setHasClaimedBattlefly(
        address user,
        uint256 battleflyType,
        uint256 value
    ) external onlyAdminAccess {
        hasClaimedBattlefly[user][battleflyType] = value;
    }

    function setHasClaimedSpecialNFT(
        address user,
        uint256 specialNFTType,
        uint256 value
    ) external onlyAdminAccess {
        hasClaimedSpecialNFT[user][specialNFTType] = value;
    }

    function setMintingTime(uint256 start, uint256 end) external onlyAdminAccess {
        StartTime = start;
        EndTime = end;
    }

    function claimBattlefly(
        uint256 allocatedAmount,
        uint256 mintingAmount,
        uint256 battleflyType,
        bytes32[] calldata proof
    ) external {
        address to = _msgSender();
        if (StartTime != 0) {
            require(block.timestamp >= StartTime, "Not start yet");
        }
        if (EndTime != 0) {
            require(block.timestamp <= EndTime, "Already finished");
        }
        require(hasClaimedBattlefly[to][battleflyType] + mintingAmount <= allocatedAmount, "Not enough allocation");
        bytes32 leaf = keccak256(abi.encodePacked(to, allocatedAmount, battleflyType));
        bool isValidLeaf = MerkleProof.verify(proof, merkleRootBattlefly, leaf);
        require(isValidLeaf, "Not in merkle");

        hasClaimedBattlefly[to][battleflyType] += mintingAmount;

        for (uint256 i = 0; i < mintingAmount; i++) {
            Game.mintBattlefly(to, battleflyType);
        }
        emit ClaimBattlefly(to, mintingAmount, battleflyType);
    }

    function claimSpecialNFT(
        uint256 allocatedAmount,
        uint256 mintingAmount,
        uint256 specialNFTType,
        bytes32[] calldata proof
    ) external {
        address to = _msgSender();
        require(hasClaimedSpecialNFT[to][specialNFTType] + mintingAmount <= allocatedAmount, "Not enough allocation");
        bytes32 leaf = keccak256(abi.encodePacked(to, allocatedAmount, specialNFTType));
        bool isValidLeaf = MerkleProof.verify(proof, merkleRootSpecialNFT, leaf);
        require(isValidLeaf, "Not in merkle");

        hasClaimedSpecialNFT[to][specialNFTType] += mintingAmount;

        for (uint256 i = 0; i < mintingAmount; i++) {
            Game.mintSpecialNFT(to, specialNFTType);
        }
        emit ClaimSpecialNFT(to, mintingAmount, specialNFTType);
    }

    modifier onlyAdminAccess() {
        require(adminAccess[_msgSender()] == true || _msgSender() == owner(), "Require admin access");
        _;
    }
}

