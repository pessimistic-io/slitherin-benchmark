// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AccountBoundToken} from "./AccountBoundToken.sol";
import "./MerkleProofLib.sol";
import "./AccessControl.sol";
import "./Pausable.sol";
import {ECDSA} from "./ECDSA.sol";

struct SBTAirdropData {
    address receiver;
    uint256 id;
    string credentialURL;
    bytes32[] proof;
}

error InvalidMerkleProof(
    address receiver,
    uint256 id,
    string credentialURL,
    bytes32[] proof
);
error InvalidSignature();
error IdHasNoRoot(uint256 id);
error InvalidSigner(address signer, address receiver);
error ReceiverNotOwner();

// _________ .__  .__                        _________                         .___
// \_   ___ \|  | |__| ________ __   ____    \_   ___ \  ___________   ____    |   | ______ ________ __   ___________
// /    \  \/|  | |  |/ ____/  |  \_/ __ \   /    \  \/ /  _ \_  __ \_/ __ \   |   |/  ___//  ___/  |  \_/ __ \_  __ \
// \     \___|  |_|  < <_|  |  |  /\  ___/   \     \___(  <_> )  | \/\  ___/   |   |\___ \ \___ \|  |  /\  ___/|  | \/
//  \______  /____/__|\__   |____/  \___  >   \______  /\____/|__|    \___  >  |___/____  >____  >____/  \___  >__|
//         \/            |__|           \/           \/                   \/            \/     \/            \/

contract CoreIssuer is AccessControl, Pausable {
    using ECDSA for bytes32;

    AccountBoundToken public ABT;
    bytes32 public constant PROJECT_ROLE = keccak256("PROJECT_ROLE");
    uint256 public _id; // _id is the next available id.
    address public _relayer;

    mapping(uint256 => bytes32) public _roots; // maps ids to roots.

    /// @notice Emitted when a merkle-root is updated.
    /// @param id The id mapped to the root.
    /// @param root The new updated root.
    event RootUpdated(uint256 id, bytes32 root);

    ///@notice Emitted when a merkle-root is added.
    ///@param id The id mapped to the root.
    ///@param root The new added root.
    event RootAdded(uint256 id, bytes32 root);

    /// @notice Emitted in the batchAirdrop when a credentail cannot be issued due to invalid-data
    /// @dev This event allows the function to succeed and infrom on failed credential issuances.
    /// @param receiver The receiver of the SBT.
    /// @param id The id of the SBT.
    /// @param credentialURL The credentialURL of the SBT.
    /// @param proof The merkle proof that the credential-data is in the merkle-tree.
    event InvalidData(
        address receiver,
        uint256 id,
        string credentialURL,
        bytes32[] proof
    );

    /// @notice Constructor sets the SBT address, id, and Access Roles.
    /// @param _ABT The address of the SBT.
    /// @param id The id of the first set of SBTs to be issued.
    constructor(address _ABT, address relayer, uint256 id) {
        ABT = AccountBoundToken(_ABT);
        _relayer = relayer;
        _id = id;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PROJECT_ROLE, msg.sender);
    }

    /// @notice Adds a merkle-root to the contract and maps it to the next available id.
    /// @param root The merkle-root to be added.
    function addRoot(bytes32 root) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _roots[_id] = root;
        emit RootAdded(_id, root);
        ++_id;
    }

    /// @notice Updates a merkle-root.
    /// @param id The id of the root to be updated.
    /// @param root The new root.
    function updateRoot(
        uint256 id,
        bytes32 root
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _roots[id] = root;
        emit RootUpdated(id, root);
    }

    /// @notice Issues a SBT to a receiver in the merkle-tree.
    /// @param receiver The receiver of the SBT.
    /// @param id The id of the SBT.
    /// @param credentialURL The credentialURL of the SBT.
    /// @param proof The merkle proof that the credential-data is in the merkle-tree.
    function issueCredential(
        address receiver,
        uint256 id,
        string calldata credentialURL,
        bytes32[] calldata proof
    ) external whenNotPaused {
        if (_roots[id] == bytes32(0)) revert IdHasNoRoot(id);
        if (!_verify(id, _leaf(receiver, id, credentialURL), proof))
            revert InvalidMerkleProof(receiver, id, credentialURL, proof);

        ABT.issue(receiver, id, credentialURL);
    }

    /// @notice Updates the credential URL of the provided receiver's SBT.
    /// @param receiver The address to receive the Phaver SBT.
    /// @param tokenId The id of the SBT.
    /// @param credentialURL URL of the caller's updated credentials.
    /// @param signature Message signed by the relayer off chain.
    function updateCredential(
        address receiver,
        uint256 tokenId,
        string memory credentialURL,
        bytes memory signature
    ) external whenNotPaused {
        bool res = ABT.ownerOf(receiver, tokenId);

        if (res != true) revert ReceiverNotOwner();
        if (msg.sender != receiver) revert InvalidSigner(msg.sender, receiver);

        bytes32 messageHash = keccak256(
            abi.encode(receiver, tokenId, credentialURL, address(this))
        );
        if (messageHash.toEthSignedMessageHash().recover(signature) != _relayer)
            revert InvalidSignature();

        ABT.update(receiver, tokenId, credentialURL);
    }

    /// @notice Aidrops SBTs to a list of receivers in the merkle-tree.
    /// @param leaves The list of credential-data to be issued.
    function airdropCredentials(
        SBTAirdropData[] calldata leaves
    ) external onlyRole(PROJECT_ROLE) whenNotPaused {
        for (uint256 i = 0; i < leaves.length; ++i) {
            if (_roots[leaves[i].id] == bytes32(0))
                revert IdHasNoRoot(leaves[i].id);
            uint256 id = leaves[i].id;
            address receiver = leaves[i].receiver;
            string calldata credentialURL = leaves[i].credentialURL;
            bytes32[] calldata proof = leaves[i].proof;
            if (!_verify(id, _leaf(receiver, id, credentialURL), proof)) {
                emit InvalidData(receiver, id, credentialURL, proof);
                continue; // If the data is invalid, skip to the next loop iteration.
            }
            ABT.issue(receiver, id, credentialURL);
        }
    }

    /// @notice Returns the ABT address.
    function getABT() public view returns (address) {
        return address(ABT);
    }

    // The owner can call this function to pause functions with "whenNotPaused" modifier.
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Sets the relayer address.
    /// @param relayer The address of the relayer.
    function setRelayer(address relayer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _relayer = relayer;
    }

    // The owner can call this function to unpause functions with "whenNotPaused" modifier.
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Constructs a merkle-tree leaf.
    /// @param receiver The receiver of the SBT.
    /// @param id The id of the SBT.
    /// @param credentialURL The credentialURL of the SBT.
    function _leaf(
        address receiver,
        uint256 id,
        string calldata credentialURL
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(receiver, id, credentialURL));
    }

    /// @notice Verifies a given leaf is in the merkle-tree with the given root.
    function _verify(
        uint256 id,
        bytes32 leaf,
        bytes32[] calldata proof
    ) internal view returns (bool) {
        bytes32 root = _roots[id];
        return MerkleProofLib.verify(proof, root, leaf);
    }
}

