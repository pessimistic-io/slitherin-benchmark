// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Owned} from "./Owned.sol";
import {MerkleProofLib} from "./MerkleProofLib.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";

/// @notice Allowlist contract for addresses.
/// @custom:oz-upgrades
contract Allowlist is UUPSUpgradeable, OwnableUpgradeable {
    /// @notice Mapping of allowed addresses.
    mapping(address => bool) public allowed;
    /// @notice Mapping of forbidden addresses.
    mapping(address => bool) public blocked;

    /// @notice If true allowed mapping is used.
    bool public allowlistRequired;
    /// @notice Merkle root for the allowlist.
    bytes32 public merkleRoot;

    event SetAllowlistRequired(bool status);
    event SetAllow(address indexed account, bool isAllowed);
    event SetBlock(address indexed account, bool isBlocked);

    error InvalidProof();
    error MisMatchArrayLength();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract.
    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
        allowlistRequired = true;
        emit SetAllowlistRequired(true);
    }

    /// @notice Implementation of the UUPS proxy authorization.
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /// @notice Checks if the address is allowed and not blacklisted.
    function canTransact(address account) public virtual view returns (bool) {
        return (!allowlistRequired || allowed[account]) && !blocked[account];
    }

    /// @notice Checks if the account is included in the merkle root.
    function verify(bytes32[] calldata proof, address account) public view returns (bool) {
        return MerkleProofLib.verify(proof, merkleRoot, keccak256(abi.encodePacked(account)));
    }

    /// @notice Publicly callable function to add an address to the allowlist using the merkle root.
    function permitAddress(bytes32[] calldata proof, address account) external {
        if (!verify(proof, account)) revert InvalidProof();
        allowed[account] = true;
        emit SetAllow(account, true);
    }

    /// @notice Toggle allowlist requirement.
    function setAllowlistRequired(bool isRequired) external onlyOwner {
        allowlistRequired = isRequired;
        emit SetAllowlistRequired(isRequired);
    }

    /// @notice Sets teh merkle root.
    function setMerkleRoot(bytes32 newMerkleRoot) external onlyOwner {
        merkleRoot = newMerkleRoot;
    }

    /// @notice Sets allowed account status.
    function allowAddress(address account, bool isAllowed) external onlyOwner {
        allowed[account] = isAllowed;
        emit SetAllow(account, isAllowed);
    }

    /// @notice Sets allowed account status for multiple accounts
    function allowAddresses(address[] calldata accounts, bool[] calldata isAllowed) external onlyOwner {
        if (accounts.length != isAllowed.length) revert MisMatchArrayLength();
        for (uint256 i = 0; i < accounts.length; i++) {
            allowed[accounts[i]] = isAllowed[i];
            emit SetAllow(accounts[i], isAllowed[i]);
        }
    }

    /// @notice Sets blocked address status.
    function blockAddress(address account, bool isBlocked) external onlyOwner {
        blocked[account] = isBlocked;
        emit SetBlock(account, isBlocked);
    }

    /// @notice Sets blocked address status for multiple accounts.
    function blockAddresses(address[] calldata accounts, bool[] calldata isBlocked) external onlyOwner {
        if (accounts.length != isBlocked.length) revert MisMatchArrayLength();
        for (uint256 i = 0; i < accounts.length; i++) {
            blocked[accounts[i]] = isBlocked[i];
            emit SetBlock(accounts[i], isBlocked[i]);
        }
    }
}

