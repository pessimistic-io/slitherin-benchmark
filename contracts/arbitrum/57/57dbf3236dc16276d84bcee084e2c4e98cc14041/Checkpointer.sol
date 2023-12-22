// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./VotesUpgradeable.sol";
import { IErrors, ITracker } from "./Interfaces.sol";
import { IRateProvider } from "./RateProvider.sol";

interface ICheckpointer {
  struct MultiplierCheckpoint {
    uint48 fromTsIncl;
    uint32 multiplier;
  }

  function isDelegationEnabled() external view returns (bool);

  function increment(address account, uint256 amount) external;

  function decrement(address account, uint256 amount) external;

  function totalSupply() external view returns (uint256);

  function getTotalSupplyWithMultiplier() external view returns (uint256);

  function getPastTotalSupplyWithMultiplier(uint256 timepoint) external view returns (uint256);

  function getVotesWithMultiplier(address account) external view returns (uint256);

  function getPastVotesWithMultiplier(address account, uint256 timepoint) external view returns (uint256);

  function getMultiplier() external view returns (uint256);

  function getPastMultiplier(uint256 timepoint) external view returns (uint256);

  function delegateOnBehalf(address account, address delegatee) external;
}

contract Checkpointer is
  Initializable,
  Ownable2StepUpgradeable,
  UUPSUpgradeable,
  VotesUpgradeable,
  IErrors,
  ICheckpointer
{
  uint private constant BASIS_POINTS_DIVISOR = 1e4;

  mapping(address => bool) public isHandler;
  ITracker public trackedToken;
  bool public isDelegationEnabled;
  MultiplierCheckpoint[] private _multiplierCheckpoints; // in basis points E.g. 1e4 = no multiplier. 13000 = 30%
  address public rateProvider;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address _trackedToken, uint32 _multiplier) public virtual initializer {
    __Ownable2Step_init();
    __UUPSUpgradeable_init();

    trackedToken = ITracker(_trackedToken);
    _pushMultiplier(_multiplier);
  }

  // total supply including exchange rate
  function totalSupply() external view returns (uint256) {
    return (_getTotalSupply() * getRate()) / BASIS_POINTS_DIVISOR;
  }

  function getTotalSupplyWithMultiplier() external view returns (uint256) {
    return (_getTotalSupply() * getMultiplier() * getRate()) / BASIS_POINTS_DIVISOR / BASIS_POINTS_DIVISOR;
  }

  function getPastTotalSupplyWithMultiplier(uint256 timepoint) external view returns (uint256) {
    return
      ((super.getPastTotalSupply(timepoint) * getPastRate(timepoint)) * getPastMultiplier(timepoint)) /
      BASIS_POINTS_DIVISOR /
      BASIS_POINTS_DIVISOR;
  }

  function getVotesWithMultiplier(address account) external view returns (uint256) {
    return (getVotes(account) * getMultiplier() * getRate()) / BASIS_POINTS_DIVISOR / BASIS_POINTS_DIVISOR;
  }

  function getPastVotesWithMultiplier(address account, uint256 timepoint) external view returns (uint256) {
    return
      (getPastVotes(account, timepoint) * getPastMultiplier(timepoint) * getPastRate(timepoint)) /
      BASIS_POINTS_DIVISOR /
      BASIS_POINTS_DIVISOR;
  }

  function getMultiplier() public view returns (uint256) {
    unchecked {
      return _multiplierCheckpoints[_multiplierCheckpoints.length - 1].multiplier;
    }
  }

  function getRate() public view returns (uint256) {
    if (rateProvider == address(0)) return BASIS_POINTS_DIVISOR;
    return IRateProvider(rateProvider).getRate();
  }

  function getPastRate(uint256 timepoint) public view returns (uint256) {
    if (rateProvider == address(0)) return BASIS_POINTS_DIVISOR;
    return IRateProvider(rateProvider).getPastRate(timepoint);
  }

  function getPastMultiplier(uint256 timepoint) public view returns (uint256) {
    require(timepoint < clock(), 'Checkpointer: future lookup');

    for (uint i = _multiplierCheckpoints.length; i > 0; ) {
      unchecked {
        MultiplierCheckpoint memory _cp = _multiplierCheckpoints[i - 1];

        if (_cp.fromTsIncl > timepoint) {
          --i;
          continue;
        } else {
          return _cp.multiplier;
        }
      }
    }

    return BASIS_POINTS_DIVISOR;
  }

  /** HANDLER */
  function increment(address account, uint256 amount) external {
    _validateHandler();

    uint256 _trackedSupply = trackedToken.totalSupply();

    if (_trackedSupply > type(uint224).max) revert FAILED('Checkpointer: total supply risks overflowing votes');

    _transferVotingUnits(address(0), account, amount);

    if (_trackedSupply != _getTotalSupply()) revert FAILED('Checkpointer: supply mismatch');
  }

  function decrement(address account, uint256 amount) external {
    _validateHandler();

    _transferVotingUnits(account, address(0), amount);

    if (trackedToken.totalSupply() != _getTotalSupply()) revert FAILED('Checkpointer: supply mismatch');
  }

  function delegateOnBehalf(address account, address delegatee) external {
    _validateHandler();
    super._delegate(account, delegatee);
  }

  /** OVERRIDES */
  function getPastTotalSupply(uint256 timepoint) public view override returns (uint256) {
    return (super.getPastTotalSupply(timepoint) * getPastRate(timepoint)) / BASIS_POINTS_DIVISOR;
  }

  function _getVotingUnits(address account) internal view override returns (uint256) {
    return trackedToken.stakedAmounts(account);
  }

  function delegateBySig(
    address delegatee,
    uint256 nonce,
    uint256 expiry,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public virtual override {
    if (isDelegationEnabled == false) revert FAILED('Checkpointer: delegation not enabled');

    super.delegateBySig(delegatee, nonce, expiry, v, r, s);
  }

  function delegate(address delegatee) public virtual override {
    if (isDelegationEnabled == false) revert FAILED('Checkpointer: delegation not enabled');

    super.delegate(delegatee);
  }

  ///@dev override clock to be timestamp based
  function clock() public view override returns (uint48) {
    return SafeCastUpgradeable.toUint48(block.timestamp);
  }

  function CLOCK_MODE() public view override returns (string memory) {
    require(clock() == block.timestamp, 'Checkpointer: broken clock mode');
    return 'mode=timestamp';
  }

  /** PRIVATE */
  function _validateHandler() private view {
    if (!isHandler[msg.sender]) revert UNAUTHORIZED('Checkpointer: !handler');
  }

  function _pushMultiplier(uint32 _multiplier) private {
    _multiplierCheckpoints.push(MultiplierCheckpoint({ fromTsIncl: clock(), multiplier: _multiplier }));
  }

  /** OWNER */
  function setRateProvider(address _rateProvider) external onlyOwner {
    rateProvider = _rateProvider;
  }

  function setMultiplier(uint32 _newMultiplier) external onlyOwner {
    _pushMultiplier(_newMultiplier);
  }

  function setHandler(address _handler, bool _isActive) external onlyOwner {
    isHandler[_handler] = _isActive;
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  function enableDelegation(bool _isEnabled) external onlyOwner {
    isDelegationEnabled = _isEnabled;
  }
}

