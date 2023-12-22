// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AccountBoundToken} from "./AccountBoundToken.sol";
import "./MerkleProofLib.sol";
import "./AccessControl.sol";
import "./Pausable.sol";
import {ECDSA} from "./ECDSA.sol";

struct SBTAirdropData {
    address receiver;
    string id;
    string credentialURL;
    bytes32[] proof;
}

struct Project {
    address projectOwner;
    uint256 tokenId;
    string  id;
    bytes32 root;
    uint256 fee;
}

error InvalidMerkleProof(
    address receiver,
    string id,
    string credentialURL,
    bytes32[] proof
);
error InvalidSignature();
error ProjectHasNoRoot(string id);
error InvalidSigner(address signer, address receiver);
error ReceiverNotOwner();
error WithdrawAddressNotSet();
error InsufficientFee();
error ProjectAlreadyExist();
error ProjectNotExist();
error CallerNotProjectOwner();


// _________ .__  .__                        _________                         .___
// \_   ___ \|  | |__| ________ __   ____    \_   ___ \  ___________   ____    |   | ______ ________ __   ___________
// /    \  \/|  | |  |/ ____/  |  \_/ __ \   /    \  \/ /  _ \_  __ \_/ __ \   |   |/  ___//  ___/  |  \_/ __ \_  __ \
// \     \___|  |_|  < <_|  |  |  /\  ___/   \     \___(  <_> )  | \/\  ___/   |   |\___ \ \___ \|  |  /\  ___/|  | \/
//  \______  /____/__|\__   |____/  \___  >   \______  /\____/|__|    \___  >  |___/____  >____  >____/  \___  >__|
//         \/            |__|           \/           \/                   \/            \/     \/            \/

contract CoreIssuerV3 is AccessControl, Pausable {
    using ECDSA for bytes32;

    AccountBoundToken public ABT;
    bytes32 public constant PROJECT_ROLE = keccak256("PROJECT_ROLE");
    uint256 public _tokenId; // available tokenId.
    address public _relayer;
    address public _withdrawAddress;
    mapping(string id => Project project) public _projects;


    /// @notice Emitted in the batchAirdrop when a credentail cannot be issued due to invalid-data
    /// @dev This event allows the function to succeed and infrom on failed credential issuances.
    /// @param receiver The receiver of the SBT.
    /// @param id The id of the Project.
    /// @param credentialURL The credentialURL of the SBT.
    /// @param proof The merkle proof that the credential-data is in the merkle-tree.
    event InvalidData(
        address receiver,
        string id,
        string credentialURL,
        bytes32[] proof
    );

    event ProjectSet(
        address projectOwner,
        uint256 tokenId,
        string  id,
        bytes32 root,
        uint256 fee
    );

     event ProjectUpdate(
        string id,
        bytes32 root,
        uint256 fee
    );


    /// @notice Modifier to check if the fee is sufficient.
    /// @param id The id of the project.
    modifier feeCheck(string calldata id) {
        if (msg.value < _projects[id].fee) revert InsufficientFee(); 
        _;
    }

    /// @notice Restricts function callers to the Relayer.
    modifier onlyRelayer() {
        require(msg.sender == _relayer, "Signer must be the Relayer");
        _;
    }


    /// @notice Constructor sets the SBT address, id, and Access Roles.
    /// @param _ABT The address of the SBT.
    /// @param tokenId The tokenId of the first set of SBTs to be issued.
    constructor(address _ABT, address relayer, address withdrawAddress, uint256 tokenId) {
        ABT = AccountBoundToken(_ABT);
        _relayer = relayer;
        _tokenId = tokenId;
        _withdrawAddress = withdrawAddress;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(PROJECT_ROLE, msg.sender);
    }


    /// @notice Sets the withdraw address.
    /// @param withdrawAddress The address of the withdraw address.
    function setWithdrawAddress(address withdrawAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _withdrawAddress = withdrawAddress;
    }


    /// @notice Withdraws the contract balance to the withdraw address.
    function withdraw() external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_withdrawAddress == address(0)) revert WithdrawAddressNotSet();
        payable(_withdrawAddress).transfer(address(this).balance);
    }

    /// @notice User mint sbt credential token in the merkle-tree.
    /// @param receiver The receiver of the SBT.
    /// @param id The id of the Project.
    /// @param credentialURL The credentialURL of the SBT.
    /// @param proof The merkle proof that the credential-data is in the merkle-tree.
    function mintCrendetial(
        address receiver,
        string calldata id,
        string calldata credentialURL,
        bytes32[] calldata proof
    ) external payable whenNotPaused feeCheck(id){
        if (_projects[id].root == bytes32(0)) revert ProjectHasNoRoot(id);
        if (!_verify(id, _leaf(receiver, credentialURL), proof))
            revert InvalidMerkleProof(receiver, id, credentialURL, proof);

        ABT.issue(receiver, _projects[id].tokenId, credentialURL);
    }

    /// @notice Relayer issues a SBT to the provided receiver address.
    /// @param receiver The receiver of the SBT.
    /// @param id The id of the Project.
    /// @param credentialURL The credentialURL of the SBT.
    /// @param proof The merkle proof that the credential-data is in the merkle-tree.
    function issueCredential(
        address receiver,
        string calldata id,
        string calldata credentialURL,
        bytes32[] calldata proof
    ) external onlyRelayer {
        if (_projects[id].root == bytes32(0)) revert ProjectHasNoRoot(id);
        if (!_verify(id, _leaf(receiver, credentialURL), proof))
            revert InvalidMerkleProof(receiver, id, credentialURL, proof);
        
        ABT.issue(receiver, _projects[id].tokenId, credentialURL);
    }

    /// @notice Updates the credential URL of the provided receiver's SBT.
    /// @param receiver The address to receive the Phaver SBT.
    /// @param id The id of the Project.
    /// @param credentialURL URL of the caller's updated credentials.
    /// @param signature Message signed by the relayer off chain.
    function updateCredential(
        address receiver,
        string calldata id,
        string memory credentialURL,
        bytes memory signature
    ) external payable whenNotPaused feeCheck(id) {
        if (_projects[id].projectOwner == address(0)) revert ProjectNotExist(); 
        uint256 tokenId = _projects[id].tokenId;
        bool res = ABT.ownerOf(receiver, tokenId);

        if (res != true) revert ReceiverNotOwner();
        if (msg.sender != receiver) revert InvalidSigner(msg.sender, receiver);

        bytes32 messageHash = keccak256(
            abi.encode(receiver, id, credentialURL, address(this))
        );
        if (messageHash.toEthSignedMessageHash().recover(signature) != _relayer)
            revert InvalidSignature();

        ABT.update(receiver, tokenId, credentialURL);
    }


    /// @notice Sets a new project with a specific id, merkle root, fee.
    /// @param id The id for this project.
    /// @param root The root of the merkle tree.
    /// @param fee The payment to claim SBT.
    function setProject(
        string calldata id,
        bytes32 root,
        uint256 fee
    ) external whenNotPaused {
        address projectOwner = msg.sender;
        if (_projects[id].projectOwner != address(0)) revert ProjectAlreadyExist(); 
        _projects[id] = Project(
            projectOwner,
            _tokenId,
            id,
            root,
            fee
        );
        emit ProjectSet(
            projectOwner,
            _tokenId,
            id,
            root,
            fee
        );
        
        ++_tokenId;
    }

    /// @notice Update existed project with a specific id, merkle root, fee.
    /// @param id The id for this project.
    /// @param root The root of the merkle tree.
    /// @param fee The payment to claim SBT.
    function updateProject(
        string calldata id,
        bytes32 root,
        uint256 fee
    ) external whenNotPaused {
       address projectOwner = msg.sender;
       if (_projects[id].projectOwner != projectOwner) revert CallerNotProjectOwner();
       _projects[id].root = root; 
       _projects[id].fee = fee;
       emit ProjectUpdate(
            id,
            root,
            fee
        );
    }

    /// @notice Aidrops SBTs to a list of receivers in the merkle-tree.
    /// @param leaves The list of credential-data to be issued.
    function airdropCredentials(
        SBTAirdropData[] calldata leaves
    ) external onlyRole(PROJECT_ROLE) whenNotPaused {
        for (uint256 i = 0; i < leaves.length; ++i) {
            if (_projects[leaves[i].id].root == bytes32(0))
                revert ProjectHasNoRoot(leaves[i].id);
            string calldata id = leaves[i].id;
            address receiver = leaves[i].receiver;
            string calldata credentialURL = leaves[i].credentialURL;
            bytes32[] calldata proof = leaves[i].proof;
            if (!_verify(id, _leaf(receiver, credentialURL), proof)) {
                emit InvalidData(receiver, id, credentialURL, proof);
                continue; // If the data is invalid, skip to the next loop iteration.
            }

            ABT.issue(receiver, _projects[id].tokenId, credentialURL);
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

    // The owner can call this function to unpause functions with "whenNotPaused" modifier.
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }


    /// @notice Sets the relayer address.
    /// @param relayer The address of the relayer.
    function setRelayer(address relayer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _relayer = relayer;
    }

    /// @notice Constructs a merkle-tree leaf.
    /// @param receiver The receiver of the SBT.
    /// @param credentialURL The credentialURL of the SBT.
    function _leaf(
        address receiver,
        string calldata credentialURL
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(receiver, credentialURL));
    }

    /// @notice Verifies a given leaf is in the merkle-tree with the given root.
    function _verify(
        string calldata id,
        bytes32 leaf,
        bytes32[] calldata proof
    ) internal view returns (bool) {
        bytes32 root = _projects[id].root;
        return MerkleProofLib.verify(proof, root, leaf);
    }
}
