// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.10;

import "./Ownable.sol";
import "./IERC20.sol";
import "./MerkleProof.sol";
import "./Crab.sol";

/**
 * @notice 
 *   Allows users to claim crab tokens depending on merkel root verification.
 */
contract CrabDistributor is Crab, Ownable {
    //*********************************************************************//
    // --------------------------- custom errors ------------------------- //
    //*********************************************************************//
    error AlreadyClaimed();
    error InvalidProof();

    // This event is triggered whenever a call to #claim succeeds.
    event Claimed(uint256 index, address account, uint256 amount);

    /**
     * @notice 
     * array to store merkel roots.
     */
    bytes32[] public root;

    /**
     * @notice 
     * user address => root => bool(claim status).
     */
    mapping(address => mapping(bytes32 => bool)) public claimed;

    constructor() Crab("Crab", "CRAB") { }

    /**
     * @notice claim tokens depending on merkel root verification
     * @param index_ proof index array
     * @param amount_ claim amount array
     * @param merkleProof_ merkel proof nested array as each proof is a array itself
     */
    function claim(uint256[] calldata index_, uint256[] calldata amount_, bytes32[][] calldata merkleProof_) public {
        // caching length
        uint256 length_ = merkleProof_.length;

        // avoid multiple SLOADS
        bytes32[] memory root_ = root;

        for (uint256 i = 0; i < length_;) {
            // pass in empty proof array where claiming not eligible
            if (merkleProof_[i].length != 0) {
                // checking if already claimed against a proof
                if (claimed[msg.sender][root_[i]]) revert AlreadyClaimed();

                // Verify the merkle proof.
                bytes32 node_ = keccak256(abi.encodePacked(index_[i], msg.sender, amount_[i]));
                if (!MerkleProof.verify(merkleProof_[i], root_[i], node_)) revert InvalidProof();

                // update the claim status for this root
                claimed[msg.sender][root_[i]] = true;

                // mint tokens
                _mint(msg.sender, amount_[i]);

                emit Claimed(index_[i], msg.sender, amount_[i]);
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice view claims status across roots for a given user
     * @param user_ address of u∏ser
     * @return claims bool array indicating whether the user has claimed against a root or not
     */
    function viewClaims(address user_) public view returns (bool[] memory claims) {
        // avoid multiple SLOADS
        bytes32[] memory root_ = root;

        // caching length
        uint256 length_ = root_.length;

        claims = new bool[](length_);

        for (uint256 i = 0; i < length_;) {
            claims[i] = claimed[user_][root_[i]];
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice update merkel root
     * @param newRoot_ new merkel root
     */
    function updateRoot(bytes32 newRoot_) external onlyOwner {
        root.push(newRoot_);
    }
}

