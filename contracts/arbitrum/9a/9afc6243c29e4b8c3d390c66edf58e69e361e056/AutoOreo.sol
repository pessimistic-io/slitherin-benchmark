// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./IVault.sol";

/**
 * @title YieldWolf Staking Contract
 * @notice handles deposits, withdraws, strategy execution and bounty rewards
 * @author YieldWolf
 */
contract AutoOreo is Ownable, ReentrancyGuard {
  using SafeERC20 for IERC20;

  struct PoolInfo {
    IERC20 stakeToken; // address of the token staked on the underlying farm
    IVault vault; // address of the vault
  }

  PoolInfo[] public poolInfo; // info of each vault
  mapping(address => bool) public vaultExists; // ensures vaults cannot be added twice

  address public feeAddress;
  address public feeAddressSetter;

  // addresses allowed to operate the vault, including pausing and unpausing it in case of emergency
  mapping(address => bool) public operators;

  event Add(IVault vault, IERC20 stakeToken);
  event SetOperator(address addr, bool isOperator);
  event SetFeeAddress(address feeAddress);
  event SetFeeAddressSetter(address feeAddressSetter);

  modifier onlyOperator() {
    require(operators[msg.sender], "onlyOperator: not allowed");
    _;
  }

  constructor(address _feeAddress) {
    operators[msg.sender] = true;
    feeAddressSetter = msg.sender;
    feeAddress = _feeAddress;
  }

  /**
   * @notice returns how many pools have been added
   */
  function poolLength() external view returns (uint256) {
    return poolInfo.length;
  }

  /**
   * @notice returns the amount of staked tokens by a user
   * @param _pid the pool id
   * @param _user address of the user
   */
  function stakedTokens(uint256 _pid, address _user) external view returns (uint256) {
    PoolInfo memory pool = poolInfo[_pid];
    IVault vault = pool.vault;
    uint256 sharesTotal = vault.totalSupply();
    return sharesTotal > 0 ? (vault.balanceOf(_user) * vault.totalStakeTokens()) / sharesTotal : 0;
  }

  /**
   * @notice adds a new vault
   * @dev can only be called by an operator
   * @param _vault address of the vault
   */
  function add(IVault _vault) public onlyOperator {
    require(!vaultExists[address(_vault)], "add: vault already exists");
    require(_vault.totalSupply() == 0, "add: pre mint not allowed");
    require(_vault.yieldWolf() == address(this), "add: invalid contract");
    IERC20 stakeToken = IERC20(_vault.stakeToken());
    poolInfo.push(PoolInfo({ stakeToken: stakeToken, vault: _vault }));
    vaultExists[address(_vault)] = true;
    emit Add(_vault, stakeToken);
  }

  /**
   * @notice transfers tokens from the user and stakes them in the underlying farm
   * @dev tokens are transferred from msg.sender directly to the vault
   * @param _pid the pool id
   * @param _depositAmount amount of tokens to transfer from msg.sender
   */
  function deposit(
    uint256 _pid,
    uint256 _depositAmount,
    bool _flag
  ) external nonReentrant {
    require(_depositAmount > 0, "deposit: cannot be zero");
    PoolInfo memory pool = poolInfo[_pid];
    IVault vault = pool.vault;
    IERC20 stakeToken = pool.stakeToken;

    if (vault.totalSupply() > 0 && _flag) {
      try vault.earn(address(0)) {} catch {}
    }

    // calculate deposit amount from balance before and after the transfer in order to support tokens with tax
    uint256 balanceBefore = stakeToken.balanceOf(address(vault));
    stakeToken.safeTransferFrom(msg.sender, address(vault), _depositAmount);
    _depositAmount = stakeToken.balanceOf(address(vault)) - balanceBefore;

    vault.deposit(msg.sender, _depositAmount);
  }

  /**
   * @notice unstakes tokens from the underlying farm and transfers them to the user
   * @dev tokens are transferred directly from the vault to the user
   * @param _pid the pool id
   * @param _withdrawAmount maximum amount of tokens to transfer to msg.sender
   */
  function withdraw(
    uint256 _pid,
    uint256 _withdrawAmount,
    bool _flag
  ) external {
    IVault vault = poolInfo[_pid].vault;
    if (_flag) {
      try vault.earn(address(0)) {} catch {}
    }

    vault.withdraw(msg.sender, _withdrawAmount);
  }

  /**
   * @notice withdraws all the token from msg.sender without running the earn
   * @dev only for emergencies
   * @param _pid the pool id
   */
  function emergencyWithdraw(uint256 _pid) external {
    IVault vault = poolInfo[_pid].vault;
    vault.withdraw(msg.sender, type(uint256).max);
  }

  /**
   * @notice adds or removes an operator
   * @dev can only be called by the owner
   * @param _addr address of the operator
   * @param _isOperator whether the given address will be set as an operator
   */
  function setOperator(address _addr, bool _isOperator) external onlyOwner {
    operators[_addr] = _isOperator;
    emit SetOperator(_addr, _isOperator);
  }

  /**
   * @notice updates the fee address
   * @dev can only be called by the fee address setter
   * @param _feeAddress new fee address
   */
  function setFeeAddress(address _feeAddress) external {
    require(msg.sender == feeAddressSetter && _feeAddress != address(0), "setFeeAddress: not allowed");
    feeAddress = _feeAddress;
    emit SetFeeAddress(_feeAddress);
  }

  /**
   * @notice updates the fee address setter
   * @dev can only be called by the previous fee address setter
   * @param _feeAddressSetter new fee address setter
   */
  function setFeeAddressSetter(address _feeAddressSetter) external {
    require(msg.sender == feeAddressSetter && _feeAddressSetter != address(0), "setFeeAddressSetter: not allowed");
    feeAddressSetter = _feeAddressSetter;
    emit SetFeeAddressSetter(_feeAddressSetter);
  }
}

