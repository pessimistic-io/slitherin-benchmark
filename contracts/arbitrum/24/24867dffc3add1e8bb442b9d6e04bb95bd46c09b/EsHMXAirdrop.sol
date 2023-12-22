// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.18;

import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";

import { IHMXStaking } from "./IHMXStaking.sol";
import { MerkleProof } from "./MerkleProof.sol";

contract EsHMXAirdrop is OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  /**
   * Errors
   */
  error EsHMXAirdrop_Initialized();
  error EsHMXAirdrop_AlreadyClaimed();
  error EsHMXAirdrop_InvalidProof();
  error EsHMXAirdrop_Unauthorized();
  error EsHMXAirdrop_InvalidClaimTimestamp();
  error EsHMXAirdrop_ClaimHasNotStarted();

  /**
   * Events
   */
  // This event is triggered whenever a call to #claim succeeds.
  event Claimed(address indexed account, uint256 amount);
  event SetFeeder(address oldFeeder, address indexed newFeeder);
  event SetHmxStaking(address oldHmxStaking, address indexed newHmsStaking);
  event Init(bytes32 merkleRoot, uint256 claimStartTimestamp);

  /**
   * States
   */

  address public token;
  address public feeder;
  address public hmxStaking;
  uint256 public claimStartTimestamp;
  bytes32 public merkleRoot;
  bool public initialized;

  mapping(address => bool) public isClaimed; // Track the status is user already claimed

  /**
   * Modifiers
   */
  modifier onlyFeederOrOwner() {
    if (msg.sender != feeder && msg.sender != owner()) revert EsHMXAirdrop_Unauthorized();
    _;
  }

  /**
   * Initialize
   */
  function initialize(address _token, address _feeder, address _hmxStaking) external initializer {
    OwnableUpgradeable.__Ownable_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    token = _token;
    feeder = _feeder;
    hmxStaking = _hmxStaking;
    IERC20Upgradeable(_token).safeApprove(_hmxStaking, type(uint256).max);
  }

  /**
   * Core Functions
   */

  function init(bytes32 _merkleRoot, uint256 _claimStartTimestamp) external onlyFeederOrOwner {
    if (initialized) revert EsHMXAirdrop_Initialized();
    if (_claimStartTimestamp < block.timestamp) revert EsHMXAirdrop_InvalidClaimTimestamp();
    merkleRoot = _merkleRoot;
    claimStartTimestamp = _claimStartTimestamp;
    initialized = true;

    emit Init(_merkleRoot, _claimStartTimestamp);
  }

  function claim(
    address _account,
    uint256 _amount,
    bytes32[] calldata _merkleProof
  ) external nonReentrant {
    _claim(_account, _amount, _merkleProof);
  }

  function emergencyWithdraw(address _receiver) external onlyOwner {
    IERC20Upgradeable tokenContract = IERC20Upgradeable(token);
    tokenContract.safeTransfer(_receiver, tokenContract.balanceOf(address(this)));
  }

  /**
   * Internal Functions
   */

  function _claim(address _account, uint256 _amount, bytes32[] calldata _merkleProof) internal {
    if (block.timestamp < claimStartTimestamp) revert EsHMXAirdrop_ClaimHasNotStarted();

    if (isClaimed[_account]) revert EsHMXAirdrop_AlreadyClaimed();

    // Verify the merkle proof.
    bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(_account, _amount))));
    if (!MerkleProof.verify(_merkleProof, merkleRoot, leaf)) revert EsHMXAirdrop_InvalidProof();

    // Mark it claimed and stake the token.
    isClaimed[_account] = true;
    IHMXStaking(hmxStaking).deposit(_account, token, _amount);
    emit Claimed(_account, _amount);
  }

  /**
   * Setter
   */

  function setFeeder(address _newFeeder) external onlyOwner {
    emit SetFeeder(feeder, _newFeeder);
    feeder = _newFeeder;
  }

  function setHmxStaking(address _newHmxStaking) external onlyOwner {
    emit SetHmxStaking(hmxStaking, _newHmxStaking);
    hmxStaking = _newHmxStaking;
  }
}

