// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./MerkleProofUpgradeable.sol";

contract MigrateRD is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeMathUpgradeable for uint256;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    struct MigratedData {
        uint256 amount;
        bool isMigrated;
    }

    mapping(address => MigratedData) public migratedData;
    address public migrateToken;
    bool public isMigrateEnabled;
    bytes32 public merkleRoot;

    event MigrateRDSucceed(address sender, uint256 amount, uint256 timestamp);

    modifier migrateEnabled() {
        require(isMigrateEnabled, "Migrate is disabled");
        _;
    }

    /**
     * @dev Withdraw Token in contract to an address, revert if it fails
     * @param recipient recipient of the transfer
     * @param token token withdraw
     */
    function withdrawFund(address recipient, address token) public onlyOwner {
        IERC20Upgradeable(token).transfer(
            recipient,
            IERC20Upgradeable(token).balanceOf(address(this))
        );
    }

    /**
     * @dev Set Merkle Root
     * @param merkleRootHash Merkle Root
     */
    function setMerkleRoot(bytes32 merkleRootHash) external onlyOwner {
        merkleRoot = merkleRootHash;
    }

    /**
     * @dev Set Token for migrate
     * @param tokenAddress token for migrate
     */
    function setMigrateToken(address tokenAddress) public onlyOwner {
        migrateToken = tokenAddress;
    }

    /**
     * @dev Set start unlock token
     */
    function startMigrate() public onlyOwner {
        require(!isMigrateEnabled, "Cannot start migrate");
        isMigrateEnabled = true;
    }

    /**
     * @dev Set stop unlock token
     */
    function stopMigrate() public onlyOwner {
        require(isMigrateEnabled, "Cannot stop migrate");
        isMigrateEnabled = false;
    }

    /**
     * @notice Verify merkle proof of the address
     */
    function verifyMigrateAddress(
        address migrateAddress,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) public view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(migrateAddress, amount));
        return MerkleProofUpgradeable.verify(merkleProof, merkleRoot, leaf);
    }

    /**
     * @dev migrate RD token
     * @param migrateAddress receipt address token
     */
    function migrate(
        address migrateAddress,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) public migrateEnabled nonReentrant {
        require(verifyMigrateAddress(migrateAddress, amount, merkleProof), "Invalid proof");
        require(!migratedData[migrateAddress].isMigrated, "The address is already migrated");

        migratedData[migrateAddress].amount = amount;
        migratedData[migrateAddress].isMigrated = true;

        IERC20Upgradeable(migrateToken).transfer(migrateAddress, amount);

        emit MigrateRDSucceed(msg.sender, amount, block.timestamp);
    }
}

