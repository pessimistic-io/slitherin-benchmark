// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "./AbstractERC20Stakeable.sol";
import "./IMintable.sol";
import "./Errors.sol";
import "./FixedPoint.sol";
import "./ERC20Upgradeable.sol";
import "./ERC20CappedUpgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./ERC20SnapshotUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./SafeCast.sol";
import "./EnumerableMap.sol";

/// @custom:security-contact security@uniwhale.co
contract UniwhaleToken is
  Initializable,
  ERC20Upgradeable,
  ERC20CappedUpgradeable,
  ERC20BurnableUpgradeable,
  ERC20SnapshotUpgradeable,
  OwnableUpgradeable,
  PausableUpgradeable,
  AccessControlUpgradeable,
  IMintable,
  AbstractERC20Stakeable,
  ReentrancyGuardUpgradeable
{
  using SafeCast for uint256;
  using FixedPoint for uint256;
  using EnumerableMap for EnumerableMap.AddressToUintMap;

  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  bool public transferrable;

  mapping(address => uint256) public emissions;

  mapping(address => uint256) internal _balances;
  mapping(address => uint256) internal _balanceLastUpdates;

  event SetTransferrableEvent(bool transferrable);
  event SetEmissionEvent(address claimer, uint256 emission);

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address owner,
    string memory name,
    string memory symbol,
    bool _transferrable,
    uint256 _cap
  ) public virtual initializer {
    __ERC20_init(name, symbol);
    __ERC20Capped_init(_cap);
    __ERC20Burnable_init();
    __ERC20Snapshot_init();
    __AccessControl_init();
    __Ownable_init();
    __Pausable_init();
    __AbstractERC20Stakeable_init();
    __ReentrancyGuard_init();

    _transferOwnership(owner);
    _grantRole(DEFAULT_ADMIN_ROLE, owner);
    _grantRole(MINTER_ROLE, owner);

    transferrable = _transferrable;
  }

  modifier canTransfer() {
    _require(
      transferrable || msg.sender == address(this),
      Errors.TRANSFER_NOT_ALLOWED
    );
    _;
  }

  modifier notContract() {
    require(tx.origin == msg.sender);
    _;
  }

  // governance functions

  function snapshot() public onlyOwner {
    _snapshot();
  }

  function pause() public onlyOwner {
    _pause();
  }

  function unpause() public onlyOwner {
    _unpause();
  }

  function setTransferrable(bool _transferrable) external onlyOwner {
    transferrable = _transferrable;
    emit SetTransferrableEvent(transferrable);
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

  function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
    _mint(to, amount);
  }

  function addBalance(uint256 amount) external override onlyRole(MINTER_ROLE) {
    _balances[msg.sender] = _balances[msg.sender]
      .add(
        emissions[msg.sender] *
          (block.number.sub(_balanceLastUpdates[msg.sender]))
      )
      .add(amount);
    _balanceLastUpdates[msg.sender] = block.number;
  }

  function removeBalance(
    uint256 amount
  ) external override onlyRole(MINTER_ROLE) {
    _balances[msg.sender] = _balances[msg.sender]
      .add(
        emissions[msg.sender] *
          (block.number.sub(_balanceLastUpdates[msg.sender]))
      )
      .sub(amount);
    _balanceLastUpdates[msg.sender] = block.number;
  }

  // external functions

  function balance() external view override returns (uint256) {
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

  function _mint(
    address to,
    uint256 amount
  )
    internal
    virtual
    override(ERC20Upgradeable, ERC20CappedUpgradeable)
    whenNotPaused
  {
    super._mint(to, amount);
  }

  function _transfer(
    address from,
    address to,
    uint256 amount
  ) internal virtual override whenNotPaused canTransfer {
    super._transfer(from, to, amount);
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  )
    internal
    virtual
    override(ERC20Upgradeable, ERC20SnapshotUpgradeable)
    whenNotPaused
  {
    super._beforeTokenTransfer(from, to, amount);
  }

  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(
    bytes4 interfaceId
  ) public view override returns (bool) {
    return
      interfaceId == type(IMintable).interfaceId ||
      super.supportsInterface(interfaceId);
  }
}

