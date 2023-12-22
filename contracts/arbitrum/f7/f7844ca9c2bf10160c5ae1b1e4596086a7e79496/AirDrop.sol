// SPDX-License-Identifier: None
pragma solidity ^0.8.4;

import "./MerkleProof.sol";
import "./IERC20.sol";

contract AirDrop {
    bytes32 public immutable root;
    uint256 public immutable rewardAmount;
    IERC20 public immutable token;
    uint256 public immutable deadline;
    mapping(address => bool) public claimed;

    constructor(bytes32 _root, uint256 _rewardAmount, address _token, uint256 _deadline) {
        root = _root;
        rewardAmount = _rewardAmount;
        token = IERC20(_token);
        deadline = _deadline;
    }

    function claim(bytes32[] calldata _proof) external {
        require(!claimed[msg.sender], "Already claimed air drop");
        require(block.timestamp <= deadline, "deadline");
        claimed[msg.sender] = true;
        bytes32 _leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender))));
        require(MerkleProof.verify(_proof, root, _leaf), "Incorrect merkle proof");
        token.transfer(msg.sender, rewardAmount);
    }
}

