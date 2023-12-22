// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";

contract Claim is Ownable {
    IERC20 public token;
    bytes32 public merkleRoot;
    mapping(address => bool) public hasClaimed;
    
    uint256 public constant CLAIM_AMOUNT = 15 * 10**18;
    bool public isClaimActive = false;

    event Claimed(address indexed user, uint256 amount);

    constructor(IERC20 _token) {
        token = _token;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function activateClaim() external onlyOwner {
        isClaimActive = true;
    }

    function changeToken(IERC20 _newToken) external onlyOwner {
        token = _newToken;
    }

    function claim(bytes32[] calldata merkleProof) external {
        require(isClaimActive, "Claim is not active");
        require(!hasClaimed[msg.sender], "Already claimed");

        
        bytes32 node = keccak256(abi.encodePacked(msg.sender, CLAIM_AMOUNT));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), "Invalid Merkle proof");

        
        hasClaimed[msg.sender] = true;
        token.transfer(msg.sender, CLAIM_AMOUNT);
        emit Claimed(msg.sender, CLAIM_AMOUNT);
    }

    function withdrawTokens() external onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No tokens to withdraw");
        token.transfer(owner(), balance);
    }
}

