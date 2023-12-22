// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./console.sol";
import "./Base.sol";

contract Bankroll is ReentrancyGuard, Ownable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  bool private stopped;
  mapping(address => bool) public games;
  mapping(address => uint256) public suspendedPlayers;
  mapping(address => mapping(address => bool)) private allowedWagers;

  event Withdrawn(address indexed owner, address indexed token, uint256 amount);
  event PayoutTransferred(address indexed player, uint256 payout, address tokenAddress);
  event AllowedWagerSet(address indexed game, address indexed tokenAddress, bool allowed);
  event AddressSuspended(address indexed player);
  event AddressUnsuspended(address indexed player);
  event GameStatusChanged(address indexed game, bool status);
  event EtherWithdrawn(address indexed owner, uint256 amount);
  event TokensWithdrawn(address indexed owner, address tokenAddress, uint256 amount);
  event OperatingStatusUpdated(bool isStopped);

  constructor() {
    stopped = false;
  }

  modifier stopInEmergency() {
    require(!stopped, "Emergency stop activated");
    _;
  }

  /**
   * @dev Changes a game's activation status.
   * @param game Address of the game to update.
   * @param status New status (true for active, false for inactive).
   */
  function setGameStatus(address game, bool status) external onlyOwner {
    require(games[game] != status, status ? "Game already added" : "Game does not exist");
    games[game] = status;
    emit GameStatusChanged(game, status);
  }

  /**
   * @dev Checks if a game is approved (active).
   * @param gameAddress Address of the game to check.
   * @return True if the game is approved, false otherwise.
   */
  function isGameApproved(address gameAddress) external view returns (bool) {
    return games[gameAddress];
  }

  /**
   * @dev Sets the wager allowance status for a specific game and token.
   * @param game Address of the game.
   * @param tokenAddress Address of the token.
   * @param status True to allow, false to disallow wagers.
   * Requires that the game's current status matches the input status.
   * Emits an AllowedWagerSet event after successful update.
   */
  function setAllowedWager(address game, address tokenAddress, bool status) external onlyOwner stopInEmergency {
    require(games[game] == status, "Game not authorized");
    allowedWagers[game][tokenAddress] = status;
    emit AllowedWagerSet(game, tokenAddress, status);
  }

  /**
   * @dev Checks if a wager is valid for a given game and token.
   * @param game Address of the game.
   * @param tokenAddress Address of the token.
   * @return True if the wager is valid, false otherwise.
   */
  function getIsValidWager(address game, address tokenAddress) external view returns (bool) {
    return allowedWagers[game][tokenAddress];
  }

  /**
   * @dev Transfers payout to a player in either native currency or a specified ERC20 token.
   * @param player Address of the player receiving the payout.
   * @param payout Amount of the payout.
   * @param tokenAddress Address of the ERC20 token (use address(0) for native currency).
   * Emits a PayoutTransferred event upon successful transfer.
   */
  function transferPayout(address player, uint256 payout, address tokenAddress) external nonReentrant stopInEmergency {
    if (tokenAddress == address(0)) {
      (bool success, ) = payable(player).call{value: payout}("");
      require(success, "transfer failed");
    } else {
      IERC20(tokenAddress).safeTransfer(player, payout);
    }
    emit PayoutTransferred(player, payout, tokenAddress);
  }

  /**
   * @dev suspendAddress: Suspends a player's address.
   * @param player Address of the player to be suspended.
   * Requires that the player is not already suspended.
   * Sets the suspension time to the current block timestamp.
   * Emits an AddressSuspended event upon suspension.
   */
  function suspendAddress(address player) external onlyOwner stopInEmergency {
    require(suspendedPlayers[player] == 0, "player already suspended");
    suspendedPlayers[player] = block.timestamp;
    emit AddressSuspended(player);
  }

  /**
   * @dev unsuspendAddress: Unsuspends a player's address.
   * @param player Address of the player to be unsuspended.
   * Requires that the player is currently suspended.
   * Resets the suspension status by updating the timestamp.
   * Emits an AddressUnsuspended event upon unsuspension.
   */
  function unsuspendAddress(address player) external onlyOwner stopInEmergency {
    require(suspendedPlayers[player] != 0, "player not suspended");
    suspendedPlayers[player] = block.timestamp;
    emit AddressUnsuspended(player);
  }

  /**
   * @dev isAddressSuspended: Checks if a player's address is suspended.
   * @param player Address of the player to check.
   * @return Boolean indicating suspension status and the timestamp of suspension.
   * Returns false and 0 if the player is not suspended.
   * Returns true and the suspension timestamp if the player is suspended.
   */
  function isAddressSuspended(address player) external view returns (bool, uint256) {
    uint256 suspendedTime = suspendedPlayers[player];

    if (suspendedTime == 0) {
      return (false, 0);
    } else {
      return (true, suspendedTime);
    }
  }

  /**
   * @dev setOperatingStatus: Sets the contract's operating status.
   * @param _isStopped Boolean to indicate the new operating status.
   * Updates the 'stopped' state variable to reflect the new status.
   * Emits an OperatingStatusUpdated event upon status change.
   */
  function setOperatingStatus(bool _isStopped) external onlyOwner {
    stopped = _isStopped;
    emit OperatingStatusUpdated(_isStopped);
  }

  /**
   * @dev getStoppedStatus: Returns the current operating status of the contract.
   * @return Boolean indicating the current operating status.
   * Returns true if the contract is stopped, false otherwise.
   */
  function getStoppedStatus() public view returns (bool) {
    return stopped;
  }

  function withdrawNative(uint256 amount) external onlyOwner stopInEmergency {
    require(amount <= address(this).balance, "Insufficient Ether balance");
    (bool success, ) = payable(msg.sender).call{value: amount}("");
    require(success, "Ether transfer failed");
    emit Withdrawn(msg.sender, address(0), amount);
  }

  function withdrawTokens(address tokenAddress, uint256 amount) external onlyOwner stopInEmergency {
    IERC20 token = IERC20(tokenAddress);
    uint256 tokenBalance = token.balanceOf(address(this));
    require(amount <= tokenBalance, "Insufficient token balance");
    token.safeTransfer(msg.sender, amount);
    // Check if the transfer was successful by comparing the token balances before and after
    uint256 newTokenBalance = token.balanceOf(address(this));
    require(tokenBalance - newTokenBalance == amount, "Token transfer failed");
    emit Withdrawn(msg.sender, tokenAddress, amount);
  }

  function withdrawAllNative() external onlyOwner stopInEmergency {
    uint256 etherBalance = address(this).balance;
    require(etherBalance > 0, "No Ether to withdraw");
    (bool success, ) = payable(msg.sender).call{value: etherBalance}("");
    require(success, "Ether withdrawal failed");
    emit EtherWithdrawn(msg.sender, etherBalance);
  }

  function withdrawAllTokens(address tokenAddress) external onlyOwner stopInEmergency {
    IERC20 token = IERC20(tokenAddress);
    uint256 tokenBalance = token.balanceOf(address(this));
    require(tokenBalance > 0, "No tokens to withdraw");
    token.safeTransfer(msg.sender, tokenBalance);
    emit TokensWithdrawn(msg.sender, tokenAddress, tokenBalance);
  }

  receive() external payable {}

  fallback() external payable {}
}

