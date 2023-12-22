// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./SafeERC20.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";

contract SHAKA_Airdrop is Ownable {
    using SafeERC20 for IERC20;
    IERC20 public constant TOKEN = IERC20(0xd9ae33E40270c51C4DcdBb23A4Bac0C8512542C2);
    uint256 public constant TOKEN_AMOUNT = 44_021_978_021_977e18;
    uint256 public baseAmount;
    mapping(address => uint256) public claimedAmounts;
    uint256 public totalClaimedAmount;
    bytes32 public arbMerkleRoot;
    bytes32 public ethMerkleRoot;
    bytes32 public memeMerkleRoot;
    bool public claimable;

    constructor() {}

    function setMerkleRoots(bytes32 _arbMerkleRoot, bytes32 _ethMerkleRoot, bytes32 _memeMerkleRoot) external onlyOwner {
        arbMerkleRoot = _arbMerkleRoot;
        ethMerkleRoot = _ethMerkleRoot;
        memeMerkleRoot = _memeMerkleRoot;
    }

    function setRule(bool _claimable, uint256 _baseAmount) external onlyOwner {
        claimable = _claimable;
        baseAmount = _baseAmount;
    }

    function withdraw(uint256 amount) external onlyOwner {
        TOKEN.safeTransfer(msg.sender, amount);
    }

    function verify(bytes32[] calldata proof, bytes32 root, bytes32 leaf) public pure returns (bool) {
        return MerkleProof.verifyCalldata(proof, root, leaf);
    }

    function getWeight(address addr, bytes32[] calldata arbProof, bytes32[] calldata ethProof, bytes32[] calldata memeProof) public view returns (uint256) {
        bytes32 leaf = keccak256(abi.encodePacked(addr));
        uint256 weight = 0;
        if (arbProof.length > 0 && verify(arbProof, arbMerkleRoot, leaf)) {
            weight = 1;
        }
        if (ethProof.length > 0 && verify(ethProof, ethMerkleRoot, leaf)) {
            weight = 3;
        }
        if (memeProof.length > 0 && verify(memeProof, memeMerkleRoot, leaf)) {
            weight += 1;
        }
        return weight;
    }

    function claim(bytes32[] calldata arbProof, bytes32[] calldata ethProof, bytes32[] calldata memeProof) external {
        require(claimable, "not claimable");
        require(claimedAmounts[msg.sender] == 0, "duplicate claim");
        uint256 weight = getWeight(msg.sender, arbProof, ethProof, memeProof);
        if (weight == 0) return;
        uint256 amount = baseAmount;
        uint256 i = (totalClaimedAmount * 10) / TOKEN_AMOUNT;
        amount -= (amount * i) / 10;
        amount *= weight;
        claimedAmounts[msg.sender] = amount;
        totalClaimedAmount += amount;
        TOKEN.safeTransfer(msg.sender, amount);
    }
}

