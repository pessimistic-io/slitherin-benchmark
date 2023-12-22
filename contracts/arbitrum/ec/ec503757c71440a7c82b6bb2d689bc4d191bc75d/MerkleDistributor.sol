//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.9;

import "./Ownable.sol";
import "./IERC20.sol";
import "./MerkleProof.sol";

import "./IMerkleDistributor.sol";

/**
 * @title MerkleDistributor is the smart contract for distributing trading rewards on the Tracer Perpetual Swaps protocol.
 * @dev Essentially a wrapper on the OpenZeppelin MerkleProof library.
 * @author dospore
 */
contract MerkleDistributor is Ownable, IMerkleDistributor {
    IERC20 public immutable token;
    // round number => merkle root
    mapping(uint256 => bytes32) public roots;
    // round number => claimant => hasClaimed
    mapping(uint256 => mapping(address => bool)) public claimed;

    event Claim(address _recipient, uint256 amount);

    constructor(address _token) public {
        require(_token != address(0), "MerkleDistributor: Invalid token address");

        token = IERC20(_token);
    }

    /**
     * @notice Modifies the underlying set for the Merkle tree. It is an error
     *          to call this function with an incorrect size or root hash.
     * @param _root The new Merkle root hash
     * @dev Only the owner of the contract can modify the Merkle set.
     */
    function setMerkleSet(
        bytes32 _root,
        uint256 round
    ) external override onlyOwner() {
        require(_root != 0, "MerkleDistributor: Invalid merkle root");
        require (roots[round] == 0, "MerkleDistributor: Root already set");

        roots[round] = _root;
    }

    /**
     * @notice Withdraws the allocated quantity of tokens to the caller
     * @param proof The proof of membership of the Merkle tree
     * @param amount The number of tokens the caller is claiming
     * @dev Marks caller as claimed if proof checking succeeds and emits the
     *      `Claim` event.
     */
    function withdraw(
        bytes32[] calldata proof,
        uint256 amount,
        uint256 round
    ) external override {
        /* check for multiple claims */
        require(!claimed[round][msg.sender], "MerkleDistributor: Already claimed");
        require (roots[round] != 0, "MerkleDistributor: Root not set");

        bytes32 root = roots[round];

        /* check the caller's Merkle proof */
        bool proofResult = MerkleProof.verify(proof, root, hash(msg.sender, amount));

        /* handle proof checking failure */
        require(proofResult, "MerkleDistributor: Invalid proof");

        /* mark caller as claimed */
        claimed[round][msg.sender] = true;

        /* transfer tokens from airdrop contract to caller */
        bool transferResult = token.transfer(msg.sender, amount);

        /* handle failure */
        require(transferResult, "MerkleDistributor: ERC20 transfer failed");

        /* emit appropriate event */
        emit Claim(msg.sender, amount);
    }

    /**
     * @notice Withdraws all tokens currently held by the airdrop contract
     * @dev Only the owner of the airdrop contract can call this method
     */
    function bail() external override onlyOwner() {
        /* retrieve current token balance of the airdrop contract */
        uint256 tokenBalance = token.balanceOf(address(this));

        /* transfer all tokens in the airdrop contract to the owner */
        bool transferResult = token.transfer(msg.sender, tokenBalance);

        require(transferResult, "MerkleDistributor: ERC20 transfer failed");
    }

    /**
     * @notice Generates the Merkle hash given address and amount
     * @param recipient The address of the recipient
     * @param amount The quantity of tokens the recipient is entitled to
     * @return The Merkle hash of the leaf node needed to prove membership
     */
    function hash(
        address recipient,
        uint256 amount
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(recipient, amount));
    }
}


