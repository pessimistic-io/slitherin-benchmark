// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.13;

/// ============ Imports ============

import "./IAuragi.sol";
import "./MerkleProof.sol";


/// @title Crew3Airdrop
contract Crew3Airdrop {
    /// @notice Auragi token to claim
    IAuragi public immutable AGI;
    /// @notice ERC20-claimee inclusion root
    bytes32 public immutable merkleRoot;
    /// @notice TOTAL airdrop 2M AGI
    uint public constant TOTAL = 2 * 1e6 * 1e18;
    
    /// @notice Receive remain tokens after airdrop ended
    address team = 0x8B4514F98e7C7727617Ebb19d5847633Fd839f45;

    uint public claimed = 0;
    uint public startTime = 1681862400; // Wed Apr 19 2023 00:00:00 GMT+0000
    uint public endTime = 1682035200; // Fri Apr 21 2023 00:00:00 GMT+0000

    /// @notice Mapping of addresses who have claimed tokens
    mapping(address => bool) public hasClaimed;


    /// @notice Creates a new MerkleClaim contract
    /// @param _agi address
    /// @param _merkleRoot of claimees
    constructor(address _agi, bytes32 _merkleRoot) {
        AGI = IAuragi(_agi);
        merkleRoot = _merkleRoot;
    }

    /// @notice Emitted after a successful token claim
    /// @param to recipient of claim
    /// @param amount of tokens claimed
    event Claim(address indexed to, uint256 amount);

    /// @notice Allows claiming tokens if address is part of merkle tree
    /// @param to address of claimee
    /// @param amount of tokens owed to claimee
    /// @param proof merkle proof to prove address and amount are in tree
    function claim(
        address to,
        uint256 amount,
        bytes32[] calldata proof
    ) external {
        // Throw if address has already claimed tokens
        require(!hasClaimed[to], "ALREADY_CLAIMED");
        require(startTime <= block.timestamp && block.timestamp <= endTime, "NOT_TIME_CLAIM");
        require(claimed + amount <= TOTAL, "OVER");

        // Verify merkle proof, or revert if not in tree
        bytes32 leaf = keccak256(abi.encodePacked(to, amount));
        bool isValidLeaf = MerkleProof.verify(proof, merkleRoot, leaf);
        require(isValidLeaf, "NOT_IN_MERKLE");

        // Set address to claimed
        hasClaimed[to] = true;

        // Claim tokens for address
        require(AGI.transfer(to, amount), "CLAIM_FAILED");
        claimed += amount;

        // Emit claim event
        emit Claim(to, amount);
    }

    /// @notice Withdraw remain tokens to team's wallet after airdrop ended
    function withdraw() external {
        require(block.timestamp > endTime, "NOT_CLAIM_END");
        uint256 _amount = AGI.balanceOf(address(this));
        AGI.transfer(team, _amount);
    }
}

