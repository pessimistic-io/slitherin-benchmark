// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "./AbstractStakeable.sol";
import "./Errors.sol";
import "./ERC20Fixed.sol";
import "./FixedPoint.sol";
import "./ERC20.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeCast.sol";

/// @custom:security-contact security@uniwhale.co
contract ERC20Staker is
  Initializable,
  OwnableUpgradeable,
  PausableUpgradeable,
  AccessControlUpgradeable,
  AbstractStakeable,
  ReentrancyGuardUpgradeable
{
  using SafeCast for uint256;
  using FixedPoint for uint256;
  using ERC20Fixed for ERC20;

  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  address stakingToken;

  mapping(address => uint256) public emissions;

  mapping(address => uint256) internal _balances;
  mapping(address => uint256) internal _balanceLastUpdates;

  event SetEmissionEvent(address claimer, uint256 emission);
  event SetStakingTokenEvent(address stakingToken);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address owner,
    address _stakingToken
  ) public virtual initializer {
    __AccessControl_init();
    __Ownable_init();
    __Pausable_init();
    __AbstractStakeable_init();
    __ReentrancyGuard_init();

    _transferOwnership(owner);
    _grantRole(MINTER_ROLE, owner);
    _grantRole(DEFAULT_ADMIN_ROLE, owner);

    stakingToken = _stakingToken;
  }

  modifier notContract() {
    require(tx.origin == msg.sender);
    _;
  }

  // governance functions

  function pause() public onlyOwner {
    _pause();
  }

  function unpause() public onlyOwner {
    _unpause();
  }

  function setStakingToken(address _stakingToken) external onlyOwner {
    stakingToken = _stakingToken;
    emit SetStakingTokenEvent(stakingToken);
  }

  function setEmission(
    address _claimer,
    uint256 _emission
  ) external virtual onlyOwner {
    if (_balanceLastUpdates[_claimer] > 0) {
      _balances[_claimer] = _balances[_claimer].add(
        emissions[_claimer] * (block.number.sub(_balanceLastUpdates[_claimer]))
      );
    }
    _balanceLastUpdates[_claimer] = block.number;
    emissions[_claimer] = _emission;
    emit SetEmissionEvent(_claimer, _emission);
  }

  function pauseStaking() external onlyOwner {
    _pauseStaking();
  }

  function unpauseStaking() external onlyOwner {
    _unpauseStaking();
  }

  function addRewardToken(IMintable rewardToken) external onlyOwner {
    _addRewardToken(rewardToken);
  }

  function removeRewardToken(IMintable rewardToken) external onlyOwner {
    _removeRewardToken(rewardToken);
  }

  // priviledged functions

  function addBalance(uint256 amount) external onlyRole(MINTER_ROLE) {
    _balances[msg.sender] = _balances[msg.sender]
      .add(
        emissions[msg.sender] *
          (block.number.sub(_balanceLastUpdates[msg.sender]))
      )
      .add(amount);
    _balanceLastUpdates[msg.sender] = block.number;
  }

  function removeBalance(uint256 amount) external onlyRole(MINTER_ROLE) {
    _balances[msg.sender] = _balances[msg.sender]
      .add(
        emissions[msg.sender] *
          (block.number.sub(_balanceLastUpdates[msg.sender]))
      )
      .sub(amount);
    _balanceLastUpdates[msg.sender] = block.number;
  }

  // external functions

  function balance() external view returns (uint256) {
    return _balance(msg.sender);
  }

  function balance(address claimer) external view returns (uint256) {
    return _balance(claimer);
  }

  function _balance(address claimer) internal view returns (uint256) {
    return
      _balances[claimer].add(
        emissions[claimer] * (block.number.sub(_balanceLastUpdates[claimer]))
      );
  }

  function stake(
    uint256 amount
  )
    external
    override
    whenNotPaused
    nonReentrant
    whenStakingNotPaused
    notContract
  {
    _stake(msg.sender, amount);
  }

  function stake(
    address _user,
    uint256 amount
  ) external override whenNotPaused nonReentrant whenStakingNotPaused {
    _require(tx.origin == _user, Errors.APPROVED_ONLY);
    _stake(_user, amount);
  }

  function unstake(
    uint256 amount
  )
    external
    override
    whenNotPaused
    nonReentrant
    whenStakingNotPaused
    notContract
  {
    _unstake(msg.sender, amount);
  }

  function claim()
    external
    override
    whenNotPaused
    nonReentrant
    whenStakingNotPaused
  {
    _claim(msg.sender);
  }

  function claim(
    address _user
  ) external override whenNotPaused nonReentrant whenStakingNotPaused {
    _claim(_user);
  }

  function claim(
    address _user,
    address _rewardToken
  ) external override whenNotPaused nonReentrant whenStakingNotPaused {
    _claim(_user, _rewardToken);
  }

  // internal functions

  function _stake(address staker, uint256 amount) internal override {
    _update(staker, amount.toInt256());
    ERC20(stakingToken).transferFromFixed(staker, address(this), amount);
    emit StakeEvent(staker, staker, amount);
  }

  function _unstake(address staker, uint256 amount) internal override {
    _require(_stakedByStaker[staker] >= amount, Errors.INVALID_AMOUNT);
    _update(staker, -amount.toInt256());
    ERC20(stakingToken).transferFixed(staker, amount);
    emit UnstakeEvent(staker, amount);
  }
}

