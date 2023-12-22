// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { Auth, GlobalACL } from "./Auth.sol";
import { MerkleProof } from "./MerkleProof.sol";

/**
 * @title Whitelist
 * @author Umami DAO
 * @notice The Whitelist contract manages a whitelist of users and their deposit limits for different assets.
 * This contract is used by aggregate vaults to ensure only authorized users can deposit specified amounts
 * of assets.
 */
contract Whitelist is GlobalACL {
    address public immutable aggregateVault;
    address public zap;

    constructor(Auth _auth, address _aggregateVault, address _zap) GlobalACL(_auth) {
        whitelistEnabled = true;
        aggregateVault = _aggregateVault;
        zap = _zap;
    }

    /// @dev asset -> user -> manual whitelist amount
    mapping(address => mapping(address => uint256)) public whitelistedDepositAmount;

    /// @dev asset -> merkle root
    mapping(address => bytes32) public merkleRoots;

    /// @dev asset -> deposit limit
    mapping(address => uint256) public merkleDepositLimit;

    /// @dev asset -> user -> total deposited
    mapping(address => mapping(address => uint256)) public merkleDepositorTracker;

    /// @dev flag for whitelist enabled
    bool public whitelistEnabled;

    event WhitelistUpdated(address indexed account, address asset, uint256 whitelistedAmount);

    // WHITELIST VIEWS
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Checks if a user has priority access to the whitelist for a specific asset.
     * @param _asset The asset address.
     * @param _account The user's address.
     */
    function isWhitelistedPriority(address _asset, address _account) external view returns (bool) {
        if (whitelistEnabled) return whitelistedDepositAmount[_account][_asset] > 0;
        return true;
    }

    /**
     * @notice Checks if a user is whitelisted using a merkle proof for a specific asset.
     * @param _asset The asset address.
     * @param _account The user's address.
     * @param merkleProof The merkle proof.
     */
    function isWhitelistedMerkle(address _asset, address _account, bytes32[] memory merkleProof)
        external
        view
        returns (bool)
    {
        bytes32 leaf = keccak256(abi.encodePacked(_account));
        if (whitelistEnabled) return MerkleProof.verify(merkleProof, merkleRoots[_asset], leaf);
        return true;
    }

    /**
     * @notice Checks if a user is whitelisted for a specific asset, using either their manual whitelist amount or merkle proof.
     * @param _asset The asset address.
     * @param _account The user's address.
     * @param merkleProof The merkle proof.
     */
    function isWhitelisted(address _asset, address _account, bytes32[] memory merkleProof)
        external
        view
        returns (bool)
    {
        bytes32 leaf = keccak256(abi.encodePacked(_account));
        if (whitelistEnabled) {
            return whitelistedDepositAmount[_account][_asset] > 0
                || MerkleProof.verify(merkleProof, merkleRoots[_asset], leaf);
        }
        return true;
    }

    // LIMIT TRACKERS
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Records a user's deposit to their whitelist amount for a specific asset.
     * @param _asset The asset address.
     * @param _account The user's address.
     * @param _amount The amount of the deposit.
     */
    function whitelistDeposit(address _asset, address _account, uint256 _amount) external onlyAggregateVaultOrZap {
        require(whitelistedDepositAmount[_account][_asset] >= _amount, "Whitelist: amount > asset whitelist amount");
        whitelistedDepositAmount[_account][_asset] -= _amount;
    }
    /**
     * @notice Records a user's deposit to their whitelist amount for a specific asset.
     * @param _asset The asset address.
     * @param _account The user's address.
     * @param _amount The amount of the deposit.
     */

    function whitelistDepositMerkle(address _asset, address _account, uint256 _amount, bytes32[] memory merkleProof)
        external
        onlyAggregateVaultOrZap
    {
        bytes32 leaf = keccak256(abi.encodePacked(_account));
        require(MerkleProof.verify(merkleProof, merkleRoots[_asset], leaf), "Whitelist: invalid proof");
        require(
            merkleDepositorTracker[_asset][_account] + _amount <= merkleDepositLimit[_asset],
            "Whitelist: amount > asset whitelist amount"
        );
        merkleDepositorTracker[_asset][_account] += _amount;
    }

    // CONFIG
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Updates the whitelist amount for a specific user and asset.
     * @param _asset The asset address.
     * @param _account The user's address.
     * @param _amount The new whitelist amount.
     */
    function updateWhitelist(address _asset, address _account, uint256 _amount) external onlyConfigurator {
        whitelistedDepositAmount[_account][_asset] = _amount;
        emit WhitelistUpdated(_account, _asset, _amount);
    }

    /**
     * @notice Updates the whitelist enabled status.
     * @param _newVal The new whitelist enabled status.
     */
    function updateWhitelistEnabled(bool _newVal) external onlyConfigurator {
        whitelistEnabled = _newVal;
    }

    /**
     * @notice Updates the merkle root for a specific asset.
     * @param _asset The asset address.
     * @param _root The new merkle root.
     */
    function updateMerkleRoot(address _asset, bytes32 _root) external onlyConfigurator {
        merkleRoots[_asset] = _root;
    }

    /**
     * @notice Updates the merkle deposit limit for a specific asset.
     * @param _asset The asset address.
     * @param _depositLimit The new limit.
     */
    function updateMerkleDepositLimit(address _asset, uint256 _depositLimit) external onlyConfigurator {
        merkleDepositLimit[_asset] = _depositLimit;
    }

    /**
     * @notice Updates the merkle depositor tracker for a specific user and asset.
     * @param _asset The asset address.
     * @param _account The user's address.
     * @param _newValue The new tracked value.
     */
    function updateMerkleDepositorTracker(address _asset, address _account, uint256 _newValue)
        external
        onlyConfigurator
    {
        merkleDepositorTracker[_asset][_account] = _newValue;
    }

    function updateZap(address _newZap) external onlyConfigurator {
        zap = _newZap;
    }

    modifier onlyAggregateVault() {
        require(msg.sender == aggregateVault, "Whitelist: only aggregate vault");
        _;
    }

    modifier onlyAggregateVaultOrZap() {
        require(msg.sender == aggregateVault || msg.sender == zap, "Whitelist: only aggregate vault or zap");
        _;
    }
}

