// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./ERC20.sol";
import "./IController.sol";

contract TGEVault {
  ERC20 public immutable underlyingToken;
  ERC20 public immutable pls;
  IController public immutable controller;
  uint256 public immutable allocation;

  mapping(address => uint256) public deposit;
  mapping(address => bool) public claimed;
  address[] public users;
  uint256 public totalDeposits;

  constructor(
    address _controller,
    address _pls,
    address _underlyingToken,
    uint256 _allocation
  ) {
    controller = IController(_controller);
    controller.addVault(address(this));
    pls = ERC20(_pls);
    underlyingToken = ERC20(_underlyingToken);
    allocation = _allocation;
  }

  function donate(uint256 _amt) external {
    require(controller.started(), 'Soon');
    require(_amt > 0, 'Amount is 0');

    uint256 _prev = underlyingToken.balanceOf(address(this));
    underlyingToken.transferFrom(msg.sender, address(this), _amt);

    require(_prev + _amt == underlyingToken.balanceOf(address(this)), 'Quantity mismatch');

    // If user's first deposit, add to list of users
    if (deposit[msg.sender] == 0) {
      users.push(msg.sender);
    }

    deposit[msg.sender] += _amt;
    totalDeposits += _amt;

    emit Donate(msg.sender, _amt);
  }

  /** CONTROLLER FUNCTIONS */
  /// @dev Should only be callable by controller, guards in controller
  function claim(address _user, address _to) external {
    require(msg.sender == address(controller), 'Unauthorized');

    claimed[_user] = true;

    uint256 plsAllocation = calculateShare(_user);
    pls.transfer(_to, plsAllocation);

    emit Claim(_user, _to, plsAllocation);
  }

  function withdrawFunds(address _to) external {
    require(msg.sender == address(controller), 'Unauthorized');
    uint256 amt = underlyingToken.balanceOf(address(this));
    underlyingToken.transfer(_to, amt);

    emit WithdrawFunds(_to, address(underlyingToken), amt);
  }

  /** GOVERNANCE FUNCTIONS */
  /// @dev Governance address can retrieve stuck funds
  function retrieve(ERC20 token) external {
    require(msg.sender == controller.governance(), 'Unauthorized');
    require(token != underlyingToken, 'token = underlying');

    if (address(this).balance > 0) {
      payable(controller.governance()).transfer(address(this).balance);
    }

    token.transfer(controller.governance(), token.balanceOf(address(this)));
  }

  /** VIEWS */
  /// @dev Get share of the allocation based on how much they deposited.
  function calculateShare(address _addr) public view returns (uint256) {
    return (allocation * deposit[_addr]) / totalDeposits;
  }

  function getUsers() external view returns (address[] memory) {
    return users;
  }

  function getUserCount() external view returns (uint256) {
    return users.length;
  }

  event Donate(address indexed user, uint256 amt);
  event WithdrawFunds(address indexed to, address underlyingToken, uint256 amt);
  event Claim(address indexed user, address to, uint256 plsAmt);
}

