// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.18;
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

import {MerkleProof} from "./MerkleProof.sol";

contract TokenClaim is ReentrancyGuard, Ownable {
    address public immutable admin;
    IERC20 public immutable token;
    bytes32 public immutable merkleRoot;

    mapping(address => bool) public isClaimed;

    event TokensClaimed(address indexed user, uint256 amount);

    constructor(address token_, bytes32 merkleRoot_) {
        admin = msg.sender;
        token = IERC20(token_);
        merkleRoot = merkleRoot_;
    }

    function claimTokens(uint256 quantity, bytes32[] calldata merkleProof) public nonReentrant {
        // ensure user hasn't already claimed
        require(!isClaimed[msg.sender], "Already claimed tokens");

        // ensure the user is actually whitelisted for the amount they have specified
        bytes32 node = keccak256(abi.encodePacked(msg.sender, quantity));
        require(
            MerkleProof.verify(merkleProof, merkleRoot, node),
            "Not whitelisted and/or for this amount (invalid proof)"
        );

        // ensure the contract has enough tokens to mint to the user
        uint256 scaledQuantity = quantity * 1e18;
        uint256 balance = token.balanceOf(address(this));
        require(balance >= scaledQuantity, "Insufficient tokens in contract");

        // transfer the tokens to the user
        require(token.transfer(msg.sender, scaledQuantity), "Token transfer failed");
        emit TokensClaimed(msg.sender, scaledQuantity);

        // set the users' status to claimed
        isClaimed[msg.sender] = true;
    }

    function removeTokens(uint256 _amount) public onlyOwner {
        uint256 balance = token.balanceOf(address(this));
        require(balance >= _amount, "Insufficient tokens in contract");
        require(token.transfer(admin, _amount), "Token transfer failed");
    }
}

