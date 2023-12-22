// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./Owned.sol";
import "./MerkleVerifier.sol";

contract Whitelist is Owned {
    mapping(address => bool) public isWhitelisted;

    bytes32 public merkleRoot;

    event Whitelisted(address indexed account, bool whitelisted);

    error InvalidProof();
    error MisMatchArrayLength();

    constructor() Owned(msg.sender) {}

    function verify(bytes32[] memory proof, address user, uint256 index) public view returns (bool) {
        return MerkleVerifier.verify(proof, merkleRoot, keccak256(abi.encodePacked(user)), index);
    }

    function whitelistAddress(bytes32[] memory proof, address user, uint256 index) external {
        if (!verify(proof, user, index)) revert InvalidProof();
        isWhitelisted[user] = true;
        emit Whitelisted(user, true);
    }

    function setMerkleRoot(bytes32 newMerkleRoot) external onlyOwner {
        merkleRoot = newMerkleRoot;
    }

    function setDirectWhitelist(address account, bool whitelisted) external onlyOwner {
        isWhitelisted[account] = whitelisted;
        emit Whitelisted(account, whitelisted);
    }

    function setDirectWhitelistBatch(address[] calldata accounts, bool[] calldata whitelisted) external onlyOwner {
        if (accounts.length != whitelisted.length) revert MisMatchArrayLength();
        for (uint256 i = 0; i < accounts.length; i++) {
            isWhitelisted[accounts[i]] = whitelisted[i];
            emit Whitelisted(accounts[i], whitelisted[i]);
        }
    }
}

