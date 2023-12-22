// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./Ownable.sol";
import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./SafeERC20.sol";

contract ASCNReserve is Ownable {
  using SafeERC20 for IERC20;

  address public multisig;
  uint256 public joinWhitelistEnd;
  uint256 public whitelistReserveStart;
  uint256 public generalReserveStart;
  uint256 public reserveEnd;
  uint256 public minUsdPerReserve;
  uint256 public maxUsdTotal;
  uint256 public currentUsdTotal;

  mapping(address => uint8) public depositTokens;
  mapping(address => bool) public whitelist;
  mapping(address => mapping(address => uint256)) public deposits;

  event Whitelist(address indexed user);
  event Reserve(address indexed user, address indexed token, uint256 amount);

  constructor(address _multisig) {
    require(_multisig != address(0), "ASCNReserve: invalid multisig");
    multisig = _multisig;
  }

  function init(
    uint256 _joinWhitelistEnd,
    uint256 _whitelistReserveStart,
    uint256 _generalReserveStart,
    uint256 _reserveEnd,
    uint256 _minUsdPerReserve,
    uint256 _maxUsdTotal
  ) external onlyOwner {
    require(
      _joinWhitelistEnd <= _whitelistReserveStart &&
      _whitelistReserveStart <= _generalReserveStart &&
      _generalReserveStart < _reserveEnd, "ASCNReserve: invalid times"
    );
    require(_minUsdPerReserve > 0, "ASCNReserve: invalid min");
    require(_maxUsdTotal > 0, "ASCNReserve: invalid max");

    joinWhitelistEnd = _joinWhitelistEnd;
    whitelistReserveStart = _whitelistReserveStart;
    generalReserveStart = _generalReserveStart;
    reserveEnd = _reserveEnd;
    minUsdPerReserve = _minUsdPerReserve;
    maxUsdTotal = _maxUsdTotal;
  }

  function setMultisig(address _multisig) external onlyOwner {
    require(multisig != address(0), "setMultisig: invalid multisig");
    multisig = _multisig;
  }

  function addDepositToken(address _token) external onlyOwner {
    require(address(_token) != address(0), "ASCNReserve: invalid token");
    require(depositTokens[address(_token)] == 0, "ASCNReserve: token already added");

    depositTokens[address(_token)] = IERC20Metadata(_token).decimals();
  }

  function removeDepositToken(address _token) external onlyOwner {
    require(depositTokens[_token] != 0, "ASCNReserve: token not added");

    delete depositTokens[_token];
  }

  // In case someone accidentally sends tokens directly to this contract
  function refund(address _token, address _to, uint256 _amount) external onlyOwner {
    IERC20(_token).safeTransfer(_to, _amount);
  }

  function joinWhitelist(address _user) external {
    require(block.timestamp < joinWhitelistEnd, "joinWhitelist: too late");
    require(whitelist[_user] == false, "joinWhitelist: already joined");

    whitelist[_user] = true;
    emit Whitelist(_user);
  }

  function reserveASCN(address _token, uint256 _amount) external {
    require(maxUsdTotal > currentUsdTotal, "reserveASCN: max total reached");
    require(block.timestamp >= whitelistReserveStart, "reserveASCN: too early");
    require(block.timestamp <= reserveEnd, "reserveASCN: too late");
    require(whitelist[msg.sender] || block.timestamp >= generalReserveStart, "reserveASCN: whitelist only");
    require(depositTokens[_token] != 0, "reserveASCN: invalid token");

    uint256 amountUsd = _amount / (10 ** depositTokens[_token]);
    require(amountUsd >= minUsdPerReserve, "reserveASCN: amount too small");

    deposits[msg.sender][_token] += _amount;
    currentUsdTotal += amountUsd;
    IERC20(_token).safeTransferFrom(msg.sender, multisig, _amount);
    emit Reserve(msg.sender, _token, _amount);
  }
}

