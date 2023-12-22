// SPDX-License-Identifier: UNLICENCED
pragma solidity ^0.8.4;

import "./Counters.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./Storage.sol";
import "./DVFAccessControl.sol";
import "./EIP712Upgradeable.sol";

abstract contract UserWallet is Storage, DVFAccessControl, EIP712Upgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  event BalanceUpdated(address indexed user, address indexed token, uint256 newBalance);
  event Deposit(address indexed user, address indexed token, uint256 amount);
  event Withdraw(address indexed user, address indexed token, uint256 amount);
  event DelegatedWithdraw(bytes32 id, address indexed user, address indexed token, uint256 amount);
  event LogEmergencyWithdrawalRequested(address indexed user, address indexed token);
  event LogEmergencyWithdrawalSettled(address indexed user, address indexed token);

  bytes32 public constant _WITHDRAW_TYPEHASH =
   keccak256("Withdraw(address user,address token,address to,uint256 amount,uint256 maxFee,uint256 nonce,uint256 deadline,uint256 chainId)");
  uint256 public constant MAX_WITHDRAWAL_DELAY = 24 hours;

  struct WithdrawConstraints {
    address user;
    address token;
    address to;
    uint256 amount;
    uint256 maxFee;
    uint256 nonce;
    uint256 deadline;
    uint256 chainId;
  }

  function __UserWallet_Init() public onlyInitializing {
      withdrawalDelay = MAX_WITHDRAWAL_DELAY;
  }
  
  /**
   * @dev Deposit tokens directly into this contract
   */
  function deposit(address _token, uint256 amount) external {
    depositTo(msg.sender, _token, amount);

    emit Deposit(msg.sender, _token, amount);
  }

  /**
   * @dev Deposit tokens directly into this contract and credit 
   * liquidity provision pool
   */
  function depositToContract(address _token, uint256 amount) external {
    depositTo(address(this), _token, amount);
  }

  /**
   * @dev Deposit tokens directly into this contract and credit {to}
   */
  function depositTo(address to, address _token, uint256 amount) public {
    IERC20Upgradeable token = IERC20Upgradeable(_token);

    uint256 balanceBefore = _contractBalance(token);
    token.safeTransferFrom(msg.sender, address(this), amount);
    uint256 amountAdded = _contractBalance(token) - balanceBefore;

    _increaseBalance(_token, to, amountAdded);
  }

  /**
   * @dev Delegated withdraw to withdraw funds on a user's behalf
   * with a valid signature
   */
  function withdraw(
    WithdrawConstraints calldata constraints,
    uint256 feeTaken,
    bytes32 withdrawalId,
    bytes memory signature
  ) external onlyRole(OPERATOR_ROLE) withUniqueId(withdrawalId) {
    ensureDeadline(constraints.deadline);
    require(feeTaken <= constraints.maxFee, 'FEE_TOO_HIGH');

    verifyWithdrawSignature(constraints, signature);

    _withdraw(constraints.user, constraints.token, constraints.amount, constraints.to);

    // Pay the fee to our liquidity pool
    transfer(constraints.user, constraints.token, address(this), feeTaken);

    // TODO find a way to merge this with withdraw
    emit DelegatedWithdraw(withdrawalId, constraints.user, constraints.token, constraints.amount);
  }

  /**
   * @dev Withdraw funds directly from this contract from liquidity pool
   */
  function withdrawFromContract(
    address _token,
    uint256 amount,
    address to
  ) external onlyRole(LIQUIDITY_SPENDER_ROLE) {
    _withdraw(address(this), _token, amount, to);
  }

  function _withdraw(address user, address _token, uint256 amount, address to) internal {
    _ensureUserBalance(user, _token, amount);

    IERC20Upgradeable token = IERC20Upgradeable(_token);

    token.safeTransfer(to, amount);

    _decreaseBalance(_token, user, amount);
  }

  /**
   * @dev Transfer funds internally between two users
   */
  function transferTo(address token, address to, uint256 amount) external {
    transfer(msg.sender, token, to, amount);
  }

  function transfer(address user, address token, address to, uint256 amount) internal {
    _ensureUserBalance(user, token, amount);
    userBalances[user][token] -= amount;
    userBalances[to][token] += amount;


    emit BalanceUpdated(user, token, userBalances[user][token]);
    emit BalanceUpdated(to, token, userBalances[to][token]);
  }

  function _increaseBalance(address token, address user, uint256 amount) internal {
    userBalances[user][token] += amount;
    tokenReserves[token] += amount;

    emit BalanceUpdated(user, token, userBalances[user][token]);
  }

  function _decreaseBalance(address token, address user, uint256 amount) internal {
    userBalances[user][token] -= amount;
    tokenReserves[token] -= amount;

    emit BalanceUpdated(user, token, userBalances[user][token]);
  }

  function _ensureUserBalance(address user, address token, uint256 amount) internal view {
    require(userBalances[user][token] >= amount, "INSUFFICIENT_FUNDS");
  }

  /**
   * @dev Unassigned token balances
   */
  function skim(address _token, address to) external onlyRole(OPERATOR_ROLE) {
    IERC20Upgradeable token = IERC20Upgradeable(_token);
    uint256 currentBalance = token.balanceOf(address(this));
    require(currentBalance > tokenReserves[_token], "NOTHING_TO_SKIM");

    token.safeTransfer(to, currentBalance - tokenReserves[_token]);
  }

  /**
   * @dev deposit unassigned funds to the contract
   */
  function skimToContract(address _token) external {
    IERC20Upgradeable token = IERC20Upgradeable(_token);
    uint256 currentBalance = token.balanceOf(address(this));
    require(currentBalance > tokenReserves[_token], "NOTHING_TO_SKIM");

    uint256 amountAdded = currentBalance - tokenReserves[_token];

    _increaseBalance(_token, address(this), amountAdded);
  }

  function _contractBalance(IERC20Upgradeable token) internal view returns (uint256) {
    return token.balanceOf(address(this));
  }

  /**
   * @dev Signature validation for the WithdrawConstraints
   */
  function verifyWithdrawSignature(
    WithdrawConstraints calldata withdrawConstraints,
    bytes memory signature
  ) private {
    require(withdrawConstraints.nonce > userNonces[withdrawConstraints.user], "NONCE_ALREADY_USED");
    require(withdrawConstraints.chainId == block.chainid, "INVALID_CHAIN");

    bytes32 structHash = _hashTypedDataV4(keccak256(
      abi.encode(
        _WITHDRAW_TYPEHASH,
        withdrawConstraints.user,
        withdrawConstraints.token,
        withdrawConstraints.to,
        withdrawConstraints.amount,
        withdrawConstraints.maxFee,
        withdrawConstraints.nonce,
        withdrawConstraints.deadline,
        withdrawConstraints.chainId
      )
    ));

    address signer = ECDSAUpgradeable.recover(structHash, signature);
    require(signer == withdrawConstraints.user, "INVALID_SIGNATURE");

    userNonces[withdrawConstraints.user] = withdrawConstraints.nonce;
  }

  // TODO de-duplicate and move to a library
  function ensureDeadline(uint256 deadline) internal view {
    // solhint-disable-next-line not-rely-on-time
    require(block.timestamp <= deadline, "DEADLINE_EXPIRED");
  }

  /**
   * @dev Set the 2 step withdrawal required delay, by default 24 hours  
   */
  function setEmergencyWithdrawalDelay(uint256 delay) external onlyRole(OPERATOR_ROLE){
    require(delay <= MAX_WITHDRAWAL_DELAY, 'WITHDRAWAL_DELAY_OVER_MAX');
    withdrawalDelay = delay;
  }

  /**
   * @dev Start emergency withdrawal
   *      Records the current timestamp, when the time elapsed exceeds ${withdrawalDelay} 
   *      funds can be requested via settleEmergencyWithdrawal
   */
  function requestEmergencyWithdrawal(address _token) external {
    emergencyWithdrawalRequests[msg.sender][_token] = block.timestamp;
    emit LogEmergencyWithdrawalRequested(msg.sender, _token);
  }

  /**
   * @dev Settle emergency withdrawal
   *      Withdraws all funds from the specified _token
   *      Balance for this token will be set to 0
   *      Emergency withdrawal timer will be reset
   */
  function settleEmergencyWithdrawal(address _token) external {
    address sender = msg.sender;
    {
      uint256 requestTimestamp = emergencyWithdrawalRequests[sender][_token];
      emergencyWithdrawalRequests[sender][_token] = 0;
      require(requestTimestamp > 0, "EMERGENCY_WITHDRAWAL_NOT_REQUESTED");
      require(requestTimestamp + withdrawalDelay < block.timestamp, "EMERGENCY_WITHDRAWAL_STILL_IN_PROGRESS");
    }
    {
      uint256 balance = userBalances[sender][_token];
      _withdraw(sender, _token, balance, sender);
    }
    emit LogEmergencyWithdrawalSettled(sender, _token);
  }
}
