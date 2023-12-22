// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.9;
pragma abicoder v2;

import {IERC20} from "./IERC20.sol";
import {SafeCast} from "./SafeCast.sol";
import {SafeERC20} from "./SafeERC20.sol";
import "./Ownable.sol";

import {IStakedToken} from "./IStakedToken.sol";
import {GamifiedVotingToken} from "./GamifiedVotingToken.sol";
import {Root} from "./Root.sol";
import "./ReentrancyGuard.sol";
import "./GamifiedTokenStructs.sol";
import "./DividendDistributorNitroPad.sol";

/**
 * @title StakedNitroPad
 * @notice StakedNitroPad is a non-transferrable ERC20 token that allows users to stake and withdraw,
 *  earning allocation launchpad rights.
 * Two main factors determine a NPAD holder’s weight in allocation:
     - Staked amount
     - Time commitment (length of time they keep the stake)
 * Stakers can unstake, after the elapsed cooldown period, and before the end of the unstake window. 
 **/
contract StakedNitroPad is GamifiedVotingToken, Ownable {
  using SafeERC20 for IERC20;
  /// @notice Core token that is staked and tracked (e.g. NPAD)
  IERC20 public immutable STAKED_TOKEN;
  /// @notice Seconds a user must wait after she initiates her cooldown before withdrawal is possible
  uint256 public COOLDOWN_SECONDS;
  /// @notice Whitelisted smart contract integrations
  mapping(address => bool) public whitelistedWrappers;

  DividendDistributorNitroPad public distributor;
  address public distributorAddress;
  uint256 private distributorGas = 200000;
  mapping(address => bool) public isDividendExempt;

  event Staked(address indexed user, uint256 amount, address delegatee);
  event Withdraw(address indexed user, address indexed to, uint256 amount);
  event Cooldown(address indexed user, uint256 percentage);
  event CooldownExited(address indexed user);
  event WrapperWhitelisted(address wallet);
  event WrapperBlacklisted(address wallet);

  /***************************************
                    INIT
    ****************************************/

  /**
   * @param _stakedToken Core token that is staked and tracked (e.g. NPAD)
   * @param _cooldownSeconds Seconds a user must wait after she initiates her cooldown before withdrawal is possible
   */
  constructor(
    address _stakedToken,
    uint256 _cooldownSeconds,
    string memory _nameArg,
    string memory _symbolArg
  ) GamifiedVotingToken(_nameArg, _symbolArg) {
    STAKED_TOKEN = IERC20(_stakedToken);
    COOLDOWN_SECONDS = _cooldownSeconds;

    distributor = new DividendDistributorNitroPad();
    distributorAddress = address(distributor);
    isDividendExempt[address(0)] = true;
  }

  /**
   * @dev Only whitelisted contracts can call core fns. mStable governors can whitelist and de-whitelist wrappers.
   * Access may be given to yield optimisers to boost rewards, but creating unlimited and ungoverned wrappers is unadvised.
   */
  modifier assertNotContract() {
    _assertNotContract();
    _;
  }

  function _assertNotContract() internal view {
    if (_msgSender() != tx.origin) {
      require(whitelistedWrappers[_msgSender()], "Not whitelisted");
    }
  }

  /***************************************
                    ACTIONS
    ****************************************/

  /**
   * @dev Stake an `_amount` of STAKED_TOKEN in the system. This amount is added to the users stake and
   * boosts their voting power.
   * @param _amount Units of STAKED_TOKEN to stake
   */
  function stake(uint256 _amount) external {
    _transferAndStake(_amount, address(0));
  }

  /**
   * @dev Transfers an `_amount` of staked tokens from sender to this staking contract
   * before calling `_settleStake`.
   * Can be overridden if the tokens are held elsewhere. eg in the Balancer Pool Gauge.
   */
  function _transferAndStake(uint256 _amount, address _delegatee) internal virtual {
    STAKED_TOKEN.safeTransferFrom(_msgSender(), address(this), _amount);
    _settleStake(_amount, _delegatee);
  }

  /**
   * @dev Gets the total number of staked tokens in this staking contract. eg NPAD .
   * Can be overridden if the tokens are held elsewhere. eg in the Balancer Pool Gauge.
   */
  function _balanceOfStakedTokens() internal view virtual returns (uint256 stakedTokens) {
    stakedTokens = STAKED_TOKEN.balanceOf(address(this));
  }

  /**
   * @dev Internal stake fn. Can only be called by whitelisted contracts/EOAs and only before a recollateralisation event.
   * NOTE - Assumes tokens have already been transferred
   * @param _amount Units of STAKED_TOKEN to stake
   * @param _delegatee Address of the user to whom the sender would like to delegate their voting power
   * return the user back to their full voting power
   */
  function _settleStake(uint256 _amount, address _delegatee) internal assertNotContract {
    require(_amount != 0, "INVALID_ZERO_AMOUNT");

    // 1. Apply the delegate if it has been chosen (else it defaults to the sender)
    if (_delegatee != address(0)) {
      _delegate(_msgSender(), _delegatee);
    }

    // 2. Deal with cooldown
    //      If a user is currently in a cooldown period, re-calculate their cooldown timestamp
    Balance memory oldBalance = _balances[_msgSender()];
    //      If we have missed the unstake window, or the user has chosen to exit the cooldown,
    //      then reset the timestamp to 0
    bool exitCooldown = (oldBalance.cooldownTimestamp > 0 &&
      block.timestamp > (oldBalance.cooldownTimestamp + COOLDOWN_SECONDS));
    if (exitCooldown) {
      emit CooldownExited(_msgSender());
    }

    // 3. Settle the stake by depositing the STAKED_TOKEN and minting voting power
    _mintRaw(_msgSender(), _amount);

    // 3. Dividend tracker
    if (!isDividendExempt[_msgSender()]) {
      try distributor.setShare(_msgSender(), balanceOf(_msgSender())) {} catch {}
    }
    emit Staked(_msgSender(), _amount, _delegatee);
  }

  /**
   * @dev Withdraw raw tokens from the system, following an elapsed cooldown period.
   * Note - May be subject to a transfer fee, depending on the users weightedTimestamp
   * @param _amount Units of raw staking token to withdraw. eg NPAD
   * @param _recipient Address of beneficiary who will receive the raw tokens
   **/
  function withdraw(uint256 _amount, address _recipient) external {
    _withdraw(_amount, _recipient);
  }

  /**
   * @dev Withdraw raw tokens from the system, following an elapsed cooldown period.
   * Note - May be subject to a transfer fee, depending on the users weightedTimestamp
   * @param _amount Units of raw staking token to withdraw. eg NPAD
   * @param _recipient Address of beneficiary who will receive the raw tokens
   **/
  function _withdraw(uint256 _amount, address _recipient) internal assertNotContract {
    require(_amount != 0, "INVALID_ZERO_AMOUNT");
    Balance memory oldBalance = _balances[_msgSender()];
    require(block.timestamp > oldBalance.cooldownTimestamp + COOLDOWN_SECONDS, "INSUFFICIENT_COOLDOWN");

    // 2. Get current balance
    Balance memory balance = _balances[_msgSender()];

    uint256 totalWithdraw = _amount;

    //      Check for percentage withdrawal
    uint256 maxWithdrawal = oldBalance.cooldownUnits;
    require(totalWithdraw <= maxWithdrawal, "Exceeds max withdrawal");

    // 5. Settle the withdrawal by burning the voting tokens
    _burnRaw(_msgSender(), totalWithdraw, false);
    // Finally transfer staked tokens back to recipient
    _withdrawStakedTokens(_recipient, totalWithdraw);
    // Dividend tracker
    if (!isDividendExempt[_msgSender()]) {
      try distributor.setShare(_msgSender(), balanceOf(_msgSender())) {} catch {}
    }
    emit Withdraw(_msgSender(), _recipient, _amount);
  }

  /**
   * @dev Transfers an `amount` of staked tokens to the withdraw `recipient`. eg NPAD.
   * Can be overridden if the tokens are held elsewhere. eg in the Balancer Pool Gauge.
   */
  function _withdrawStakedTokens(address _recipient, uint256 amount) internal virtual {
    STAKED_TOKEN.safeTransfer(_recipient, amount);
  }

  /**
   * @dev Enters a cooldown period, after which (and before the unstake window elapses) a user will be able
   * to withdraw part or all of their staked tokens. Note, during this period, a users voting power is significantly reduced.
   * If a user already has a cooldown period, then it will reset to the current block timestamp, so use wisely.
   * @param _units Units of stake to cooldown for
   **/
  function startCooldown(uint256 _units) external {
    _startCooldown(_units);
  }

  /**
   * @dev Ends the cooldown of the sender and give them back their full voting power. This can be used to signal that
   * the user no longer wishes to exit the system. Note, the cooldown can also be reset, more smoothly, as part of a stake or
   * withdraw transaction.
   **/
  function endCooldown() external {
    require(_balances[_msgSender()].cooldownTimestamp != 0, "No cooldown");

    _exitCooldownPeriod(_msgSender());

    emit CooldownExited(_msgSender());
  }

  /**
   * @dev Enters a cooldown period, after which (and before the unstake window elapses) a user will be able
   * to withdraw part or all of their staked tokens. Note, during this period, a users voting power is significantly reduced.
   * If a user already has a cooldown period, then it will reset to the current block timestamp, so use wisely.
   * @param _units Units of stake to cooldown for
   **/
  function _startCooldown(uint256 _units) internal {
    require(balanceOf(_msgSender()) != 0, "INVALID_BALANCE_ON_COOLDOWN");

    _enterCooldownPeriod(_msgSender(), _units);

    emit Cooldown(_msgSender(), _units);
  }

  /***************************************
                    ADMIN
    ****************************************/

  /**
   * @dev Allows governance to whitelist a smart contract to interact with the StakedToken (for example a yield aggregator or simply
   * a Gnosis SAFE or other)
   * @param _wrapper Address of the smart contract to list
   **/
  function whitelistWrapper(address _wrapper) external onlyOwner {
    whitelistedWrappers[_wrapper] = true;

    emit WrapperWhitelisted(_wrapper);
  }

  /**
   * @dev Allows governance to blacklist a smart contract to end it's interaction with the StakedToken
   * @param _wrapper Address of the smart contract to blacklist
   **/
  function blackListWrapper(address _wrapper) external onlyOwner {
    whitelistedWrappers[_wrapper] = false;

    emit WrapperBlacklisted(_wrapper);
  }

  function setCooldownSeconds(uint256 _cooldownSeconds) external onlyOwner {
    COOLDOWN_SECONDS = _cooldownSeconds;
  }

  // Add extra rewards to holders
  function deposit(uint256 _amount) external onlyOwner {
    try distributor.deposit(_amount) {} catch {}
  }

  // Process rewards distributions to holders
  function process() external onlyOwner {
    try distributor.process(distributorGas) {} catch {}
  }

  function setIsDividendExempt(address holder, bool exempt) external onlyOwner {
    isDividendExempt[holder] = exempt;
    if (exempt) {
      distributor.setShare(holder, 0);
    } else {
      distributor.setShare(holder, balanceOf(holder));
    }
  }

  function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external onlyOwner {
    distributor.setDistributionCriteria(_minPeriod, _minDistribution);
  }

  function setDistributorSettings(uint256 gas) external onlyOwner {
    require(gas < 900000);
    distributorGas = gas;
  }

  /**
   * @dev Move rewards power when tokens are transferred.
   */
  function _afterTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal virtual override {
    if (!isDividendExempt[from]) {
      try distributor.setShare(from, balanceOf(from)) {} catch {}
    }
    if (!isDividendExempt[to]) {
      try distributor.setShare(to, balanceOf(to)) {} catch {}
    }
  }

  /***************************************
                    GETTERS
    ****************************************/

  uint256[48] private __gap;
}

