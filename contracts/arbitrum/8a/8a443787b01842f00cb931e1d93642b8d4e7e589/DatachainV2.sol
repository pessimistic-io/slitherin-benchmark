// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import "./PausableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./CartesiMathMerkle.sol";

/// @title On-chain contract for Tosi
/// @dev This contract is used by Tosi, no manual calls needed
contract DatachainV2 is Initializable, OwnableUpgradeable, UUPSUpgradeable, CartesiMathMerkle {
  uint256 private constant CARTESI_MERKLE_LOG2_SIZE = 18;

  uint256 public blockNumber;
  address public coordinatorNode;
  bytes32 public latestBlockHash;

  mapping(uint256 => bytes32) private blockHashes;
  mapping(uint256 => bytes32) private merkleHashes; // obsolete
  mapping(uint256 => uint256) private blockTimestamps;

  uint256 public previousVersion;

  event BlockSubmitted();

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Constructor for upgradeable contract.
  /// @dev Initializes all the inherited contracts.
  /// @param _coordinatorNode Address of the coordinator node.
  function initialize(address _coordinatorNode) public initializer {
    __Ownable_init();
    __UUPSUpgradeable_init();
    coordinatorNode = _coordinatorNode;
  }

  /// @notice Submits block and stores relevant data.
  /// @dev Stores blockHash and timestamp which can be retrieved using getters.
  ///      Also emits an event.
  /// @param _block Block to submit.
  function submitBlock(bytes calldata _block) external {
    require(msg.sender == coordinatorNode, "Only the coordinator node can submit blocks");
    uint256 callDataLength = _block.length;

    require(callDataLength >= 4, "Data must be at least 4 bytes");
    require(callDataLength < (256*1024 + 1), "Block cannot be beyond 256kb");

    bytes4 version;
    assembly {
      version := calldataload(_block.offset)
    }
 
    // this is a hacky protobuf decoder
    if (previousVersion == 0x08011220) {
      if (uint32(version) != 0x08011220) {
        revert("unsupported version upgrade");
      }
      require(callDataLength >= 36, "Data must be at least 36 bytes");
      bytes32 prevBlockHash;
      assembly {
        prevBlockHash := calldataload(add(_block.offset, 4))
      }
      require(prevBlockHash == latestBlockHash, "Previous block hash must be equal to latest");
    } else if (previousVersion == 0) {
      if (uint32(version) == 0x08011220) {
        previousVersion = uint32(version);
      } else {
        revert("unsupported version upgrade");
      }
    } else {
      revert("unsupported version");
    }

    blockNumber++;



    latestBlockHash = keccak256(_block);

    blockHashes[blockNumber] = latestBlockHash;
    blockTimestamps[blockNumber] = block.timestamp;

    emit BlockSubmitted();
  }

  /// @notice Returns the hash of a specified block.
  /// @dev This function is read-only and does not modify the contract's state.
  /// @param blockIndex The index of the block to get the hash for.
  /// @return The hash of the specified block.
  function blockHash(uint256 blockIndex) external view returns (bytes32) {
    return blockHashes[blockIndex];
  }

  /// @notice Get the Merkle hash of a specified block.
  /// @dev This function is read-only and does not modify the contract's state.
  /// @param blockIndex The index of the block to get the Merkle hash for.
  /// @return The Merkle hash of the specified block.
  function getMerkleHash(uint256 blockIndex) external view returns (bytes32) {
    revert();
  }

  /// @notice Get the timestamp of a specified block.
  /// @dev This function is read-only and does not modify the contract's state.
  /// @param blockIndex The index of the block to get the timestamp for.
  /// @return The timestamp of the specified block.
  function getBlockTimestamp(uint256 blockIndex) external view returns (uint256) {
    return blockTimestamps[blockIndex];
  }

  /// @notice Get the address of the current implementation of the contract.
  /// @dev This function is read-only and does not modify the contract's state.
  /// @return The address of the current implementation of the contract.
  function getImplementation() external view returns (address) {
    return _getImplementation();
  }

  /// @notice Authorize an upgrade to a new contract implementation.
  /// @dev This function is called by the contract's upgradeability mechanism.
  ///      It can only be called by the owner of the contract.
  /// @param newImplementation The address of the new contract implementation to authorize.
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

  /// @notice Set the address of the coordinator node.
  /// @dev This function can only be called by the owner of the contract.
  /// @param newCoordinatorNode The address of the new coordinator node to set.
  function setCoordinatorNode(address newCoordinatorNode) external onlyOwner {
    coordinatorNode = newCoordinatorNode;
  }
}

