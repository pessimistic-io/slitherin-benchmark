// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { IERC20Upgradeable } from "./ERC20_IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

import { MerkleProof } from "./MerkleProof.sol";

contract MerkleAirdrop is OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  /**
   * Errors
   */
  error MerkleAirdrop_Initialized();
  error MerkleAirdrop_AlreadyClaimed();
  error MerkleAirdrop_InvalidProof();
  error MerkleAirdrop_CannotInitFutureWeek();
  error MerkleAirdrop_Unauthorized();

  /**
   * Events
   */
  // This event is triggered whenever a call to #claim succeeds.
  event Claimed(uint256 weekNumber, address account, uint256 amount);
  event SetFeeder(address oldFeeder, address newFeeder);
  event Init(uint256 weekNumber, bytes32 merkleRoot);

  /**
   * States
   */

  address public token;
  address public feeder;
  mapping(uint256 => bytes32) public merkleRoot; // merkleRoot mapping by week timestamp
  mapping(uint256 => bool) public initialized;

  // This is a packed array of booleans.
  mapping(uint256 => mapping(address => bool)) public isClaimed; // Track the status is user already claimed in the given weekTimestamp

  /**
   * Modifiers
   */
  modifier onlyFeederOrOwner() {
    if (msg.sender != feeder && msg.sender != owner()) revert MerkleAirdrop_Unauthorized();
    _;
  }

  /**
   * Initialize
   */

  function initialize(address token_, address feeder_) external initializer {
    OwnableUpgradeable.__Ownable_init();

    token = token_;
    feeder = feeder_;
  }

  /**
   * Core Functions
   */

  function init(uint256 weekNumber, bytes32 merkleRoot_) external onlyFeederOrOwner {
    uint256 currentWeekNumber = block.timestamp / (60 * 60 * 24 * 7);
    if (currentWeekNumber <= weekNumber) revert MerkleAirdrop_CannotInitFutureWeek();
    if (initialized[weekNumber]) revert MerkleAirdrop_Initialized();

    merkleRoot[weekNumber] = merkleRoot_;
    initialized[weekNumber] = true;

    emit Init(weekNumber, merkleRoot_);
  }

  function claim(
    uint256 weekNumber,
    address account,
    uint256 amount,
    bytes32[] calldata merkleProof
  ) external {
    _claim(weekNumber, account, amount, merkleProof);
  }

  function bulkClaim(
    uint256[] calldata weekNumbers,
    address[] calldata accounts,
    uint256[] calldata amounts,
    bytes32[][] calldata merkleProof
  ) external {
    uint256 _len = weekNumbers.length;
    for (uint256 i; i < _len; ) {
      _claim(weekNumbers[i], accounts[i], amounts[i], merkleProof[i]);
      unchecked {
        ++i;
      }
    }
  }

  function emergencyWithdraw(address receiver) external onlyOwner {
    IERC20Upgradeable tokenContract = IERC20Upgradeable(token);
    uint256 balance = tokenContract.balanceOf(address(this));
    tokenContract.safeTransfer(receiver, balance);
  }

  /**
   * Internal Functions
   */

  function _claim(
    uint256 weekNumber,
    address account,
    uint256 amount,
    bytes32[] calldata merkleProof
  ) internal {
    if (isClaimed[weekNumber][account]) revert MerkleAirdrop_AlreadyClaimed();

    // Verify the merkle proof.
    bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(account, amount))));
    if (!MerkleProof.verify(merkleProof, merkleRoot[weekNumber], leaf))
      revert MerkleAirdrop_InvalidProof();

    // Mark it claimed and send the token.
    isClaimed[weekNumber][account] = true;

    IERC20Upgradeable(token).safeTransfer(account, amount);

    emit Claimed(weekNumber, account, amount);
  }

  /**
   * Setter
   */

  function setFeeder(address newFeeder) external onlyOwner {
    emit SetFeeder(feeder, newFeeder);
    feeder = newFeeder;
  }
}

