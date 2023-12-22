// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./MerkleProof.sol";
import "./AccessControl.sol";
import "./Pausable.sol";
import "./ISmolRingDistributor.sol";

/**
 * @title  SmolRingDistributor contract
 * @author Archethect
 * @notice This contract contains all functionalities for distributing Smol Rings following a whitelist.
 */
contract SmolRingDistributor is AccessControl, Pausable, ISmolRingDistributor {
    bytes32[] public merkleRoots;
    uint256 public claimed = 0;

    // This is a packed array of booleans.
    mapping(address => mapping(uint256 => uint256)) private claimedBitMap;

    // This event is triggered whenever a call to #claim succeeds.
    event Claimed(address account, uint256 lastEpoch, uint256 amount, uint256[] rings);
    // This event is triggered whenever a call to #claim succeeds.
    event BatchClaimed(address account, uint256[] epochs, uint256[] amounts, uint256[][] rings);
    /// @dev The identifier of the role which maintains other roles.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    /// @dev The identifier of the role which allows accounts to operate distributions.
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");

    constructor(address admin, address smolRings) {
        require(address(admin) != address(0), "SMOLRINGDISTRIBUTOR:ILLEGAL_ADMIN_ADDRESS");
        require(address(smolRings) != address(0), "SMOLRINGDISTRIBUTOR:ILLEGAL_ADMIN_ADDRESS");
        _setupRole(OPERATOR_ROLE, admin);
        _setupRole(OPERATOR_ROLE, smolRings);
        _setupRole(ADMIN_ROLE, admin);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
    }

    modifier onlyOperator() {
        require(hasRole(OPERATOR_ROLE, msg.sender), "SMOLRINGDISTRIBUTOR:ACCESS_DENIED");
        _;
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "SMOLRINGDISTRIBUTOR:ACCESS_DENIED");
        _;
    }

    /**
     * @notice Check if account has claimed during epoch
     * @param account address of the claimer
     * @param epoch epoch to claim from
     */
    function isClaimed(address account, uint256 epoch) public view returns (bool) {
        uint256 claimedWordIndex = epoch / 256;
        uint256 claimedBitIndex = epoch % 256;
        uint256 claimedWord = claimedBitMap[account][claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function getCurrentEpoch() external view returns (uint256) {
        return merkleRoots.length - 1;
    }

    function _setClaimed(address account, uint256 epoch) private {
        uint256 claimedWordIndex = epoch / 256;
        uint256 claimedBitIndex = epoch % 256;
        claimedBitMap[account][claimedWordIndex] = claimedBitMap[account][claimedWordIndex] | (1 << claimedBitIndex);
    }

    /**
     * @notice Verify and claim the ownership of rings using merkleproofs
     * @param account address of the claimer
     * @param epochToClaim epoch to claim from
     * @param index index of the claim
     * @param rings array of amount of rings per type
     * @param merkleProof merkleproof of claim
     */
    function verifyAndClaim(
        address account,
        uint256 epochToClaim,
        uint256 index,
        uint256 amount,
        uint256[] calldata rings,
        bytes32[] calldata merkleProof
    ) public whenNotPaused onlyOperator returns (bool) {
        uint256 currentEpoch = merkleRoots.length - 1;
        require(epochToClaim <= currentEpoch, "SMOLRINGDISTRIBUTOR:INVALID_EPOCH");
        require(!isClaimed(account, epochToClaim), "SMOLRINGDISTRIBUTOR:EPOCH_ALREADY_CLAIMED");
        require(
            _verifyMerkleProof(_leaf(account, epochToClaim, index, amount, rings), epochToClaim, merkleProof),
            "SMOLRINGDISTRIBUTOR:INVALID_PROOF"
        );
        _setClaimed(account, epochToClaim);
        emit Claimed(account, epochToClaim, amount, rings);
        return true;
    }

    function _leaf(
        address account,
        uint256 epoch,
        uint256 index,
        uint256 amount,
        uint256[] memory rings
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(index, account, epoch, amount, rings));
    }

    function _verifyMerkleProof(
        bytes32 leaf,
        uint256 epoch,
        bytes32[] memory proof
    ) internal view returns (bool) {
        return MerkleProof.verify(proof, merkleRoots[epoch], leaf);
    }

    /**
     * @notice Set a new root for an existing epoch
     * @param epoch epoch to set the root for
     * @param root new merkleroot
     * @param pause_ if the contract should be paused
     */
    function emergencySetRoot(
        uint256 epoch,
        bytes32 root,
        bool pause_
    ) external onlyOperator {
        merkleRoots[epoch] = root;
        if (pause_) {
            _pause();
        }
    }

    /**
     * @notice Add a new merkleroot for a new epoch
     * @param root new merkleroot
     * @param pause_ if the contract should be paused
     */
    function addRoot(bytes32 root, bool pause_) external onlyOperator {
        merkleRoots.push(root);
        if (pause_) {
            _pause();
        }
    }

    function pause() external onlyOperator {
        _pause();
    }

    function unpause() external onlyOperator {
        _unpause();
    }
}

