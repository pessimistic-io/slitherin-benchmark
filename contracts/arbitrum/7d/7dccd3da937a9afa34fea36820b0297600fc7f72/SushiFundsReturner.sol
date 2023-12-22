// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./MerkleProof.sol";
import "./Ownable.sol";

contract SushiFundsReturner is Ownable {
    bytes32 public merkleRoot;
    bool public frozen = false;

    // This event is triggered whenever a call to #claim succeeds.
    event Claimed(uint256 index, uint256 amount, address indexed account, address indexed token);

    // This is a packed array of booleans.
    mapping(uint256 => uint256) private claimedBitMap;

    constructor(bytes32 _merkleRoot) {
        merkleRoot = _merkleRoot;
    }

    function isClaimed(uint256 index) public view returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[claimedWordIndex] = claimedBitMap[claimedWordIndex] | (1 << claimedBitIndex);
    }

    function claim(uint256 index, address account, uint256 amount, address token, bytes32[] calldata merkleProof) external {
        require(!frozen, 'MerkleDistributor: Claiming is frozen.');
        require(!isClaimed(index), 'MerkleDistributor: Drop already claimed.');

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, amount, token));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), 'MerkleDistributor: Invalid proof.');

        // Mark it claimed and send the token.
        _setClaimed(index);
        require(IERC20(token).transfer(account, amount), 'MerkleDistributor: Transfer failed.');

        emit Claimed(index, amount, account, token);
    }

    function freeze(bool _freeze) public onlyOwner {
        frozen = _freeze;
    }

    function yoink(address token) public onlyOwner {
        require(IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this))), 'MerkleDistributor: Transfer failed.');
    }
}

