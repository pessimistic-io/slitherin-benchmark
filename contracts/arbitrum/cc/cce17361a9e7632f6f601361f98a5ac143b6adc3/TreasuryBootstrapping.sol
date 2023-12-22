//SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import { IERC20Metadata as IERC20 } from "./IERC20Metadata.sol";
import { MerkleProof } from "./MerkleProof.sol";

import "./GovernanceInitiationData.sol";
import "./GovernanceErrors.sol";

error InvalidContributionAmount();
error NotWhitelistedContributor();
error ExistingContributor();
error InvalidStartTimestamp();
error ContributionSizeReached();
error NotFinishedYet();
error InvalidProof();
error NotStartedYet();
error NotApprovedYet();
error InvalidDeployedState();
error AlreadyApproved();
error InvalidAmount();
error AmountPerUnitNotSet();

contract TreasuryBootstrapping {
  GovernanceInitiationData public initiationData;

  IERC20 public immutable coraToken;
  IERC20 public stablecoinToken;

  uint256 public constant SUPPLY_FOR_BOOTSTRAPPING = 10_000_000 ether; // 10M
  uint256 public constant SUPPLY_PERCENTAGE = 0.1 ether; // 10%

  // Computed values to be set once proposal is approved
  uint256 public startTimeStamp;
  uint256 public amountPerUnit;
  uint256 public totalContributions;

  enum State {
    Deployed,
    Approved,
    Started,
    Settled,
    Cancelled
  }

  State private state;

  // Parameters to start the bootstrapping
  uint256 public fdv;
  uint256 public targetAmount;
  uint256 public duration;
  uint256 public privatePeriod;
  address public beneficiary;
  uint256 public minContributionSize;
  uint256 public maxContributionSize;
  bytes32 public merkleRoot;

  mapping(address contributor => bool contributed) public hasContributed;

  mapping(address contributor => uint256 amount) public contributionsPerAddress;

  constructor(GovernanceInitiationData _initiationData) {
    coraToken = IERC20(_initiationData.tokenAddress());

    // explicitly assert this condition to give transparency to the DAO
    uint256 totalSupplyComputed = coraToken.totalSupply() * SUPPLY_PERCENTAGE / 1 ether;

    assert(totalSupplyComputed == SUPPLY_FOR_BOOTSTRAPPING);

    initiationData = _initiationData;

    state = State.Deployed;
  }

  // EXTERNAL FUNCTIONS
  function approveAndSchedule(
    uint256 _fdv,
    uint256 _targetAmount,
    uint256 _duration,
    uint256 _privatePeriod,
    address _beneficiary,
    uint256 _minContributionSize,
    uint256 _maxContributionSize,
    uint256 _startTimeAfterApproval,
    address _stablecoinToken,
    bytes32 _merkleRoot
  ) external whenDeployed onlyDao {
    fdv = _fdv;
    targetAmount = _targetAmount;
    duration = _duration;
    privatePeriod = _privatePeriod;
    beneficiary = _beneficiary;
    minContributionSize = _minContributionSize;
    maxContributionSize = _maxContributionSize;
    merkleRoot = _merkleRoot;
    stablecoinToken = IERC20(_stablecoinToken);

    startTimeStamp = block.timestamp + _startTimeAfterApproval;
    amountPerUnit = _targetAmount * 1 ether / SUPPLY_FOR_BOOTSTRAPPING;
    state = State.Approved;
  }

  function cancel() external whenDeployed onlyDao {
    if (state == State.Approved) {
      revert AlreadyApproved();
    }
    uint256 remainingTokens = coraToken.balanceOf(address(this));
    state = State.Cancelled;
    coraToken.transfer(initiationData.timelockAddress(), remainingTokens);
  }

  // bootstrap when started
  function bootstrap(uint256 _amount, uint256 _index, bytes32[] calldata _merkleProof)
    external
    whenApproved
    whenStarted
    onlyValidAmounts(_amount)
  {
    // @dev Verify if contributor is whitelisted
    if (_isInPrivatePeriod()) {
      _verifyIfWhitelisted(_index, msg.sender, _merkleProof);
    }

    // @dev Verify hasn't reach its limits
    uint256 contributionsBySender = contributionsPerAddress[msg.sender];

    if (contributionsBySender + _amount > maxContributionSize) {
      revert ContributionSizeReached();
    }

    if (!hasContributed[msg.sender]) {
      hasContributed[msg.sender] = true;
    }

    uint256 amountTokensToReceive = calculateAmount(_amount);
    totalContributions += _amount;
    contributionsPerAddress[msg.sender] += _amount;
    stablecoinToken.transferFrom(msg.sender, address(this), _amount);
    coraToken.transfer(msg.sender, amountTokensToReceive);
  }

  /**
    @notice Settles the treasury bootstrapping event by transferring the remaining cora tokens to the DAO and the stablecoins to the beneficiary.
   */
  function settle() external whenApproved whenFinished {
    state = State.Settled;
    uint256 amountOfStables = stablecoinToken.balanceOf(address(this));
    uint256 remainingTokens = coraToken.balanceOf(address(this));
    coraToken.transfer(initiationData.timelockAddress(), remainingTokens);
    stablecoinToken.transfer(beneficiary, amountOfStables);
  }

  // INTERNAL FUNCTIONS
  function _isInPrivatePeriod() internal view returns (bool) {
    return block.timestamp < startTimeStamp + privatePeriod;
  }

  function _verifyIfWhitelisted(uint256 _index, address _account, bytes32[] memory _merkleProof)
    internal
    view
  {
    // Verify the merkle proof.
    bytes32 node = keccak256(abi.encodePacked(_index, _account));
    if (!MerkleProof.verify(_merkleProof, merkleRoot, node)) {
      revert InvalidProof();
    }
  }

  // MODIFIERS
  modifier whenFinished() {
    if (block.timestamp < getEndDate()) {
      revert NotFinishedYet();
    }
    _;
  }

  modifier onlyValidAmounts(uint256 _amount) {
    // @dev only multiples of amountPerUnit
    if (_amount % amountPerUnit != 0) {
      revert InvalidContributionAmount();
    }
    _;
  }

  modifier whenStarted() {
    if (block.timestamp < startTimeStamp) {
      revert NotStartedYet();
    }
    _;
  }

  modifier whenApproved() {
    if (state != State.Approved) {
      revert NotApprovedYet();
    }
    _;
  }

  modifier whenDeployed() {
    if (state != State.Deployed) {
      revert InvalidDeployedState();
    }
    _;
  }

  modifier onlyDao() {
    if (msg.sender != initiationData.timelockAddress()) {
      revert OnlyDAO();
    }
    _;
  }

  // GETTERS
  function calculateAmount(uint256 _LUSDAmount) public view returns (uint256) {
    if (_LUSDAmount == 0) {
      revert InvalidAmount();
    }
    if (amountPerUnit == 0) {
      revert AmountPerUnitNotSet();
    }
    return _LUSDAmount / amountPerUnit * 1 ether;
  }

  function getEndDate() public view returns (uint256) {
    return startTimeStamp + duration;
  }

  function getEndOfPrivatePeriod() public view returns (uint256) {
    return startTimeStamp + privatePeriod;
  }

  function getRemainingTokens() public view returns (uint256) {
    return coraToken.balanceOf(address(this));
  }

  function getStablesBalance() public view returns (uint256) {
    return stablecoinToken.balanceOf(address(this));
  }

  function getStatus() public view returns (State) {
    if (state == State.Approved && block.timestamp > startTimeStamp) {
      return State.Started;
    }
    return state;
  }
}

