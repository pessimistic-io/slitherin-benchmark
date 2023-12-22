// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Pausable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./Address.sol";

import { IStaker } from "./interfaces.sol";
import "./ITokenMinter.sol";
import { IWhitelist } from "./Whitelist.sol";

contract SpaDepositor is Ownable, Pausable {
  using SafeERC20 for IERC20;

  IERC20 public immutable token;
  IERC20 public immutable escrow;
  address public immutable minter; // plsAsset
  address public immutable staker;

  IWhitelist public whitelist;

  constructor(
    address _token,
    address _escrow,
    address _staker,
    address _minter
  ) {
    token = IERC20(_token);
    escrow = IERC20(_escrow);
    staker = _staker;
    minter = _minter;
    _pause();
  }

  /**
   * Deposit asset for plsAsset
   */
  function deposit(uint256 _amount) public whenNotPaused {
    _isEligibleSender();
    _deposit(msg.sender, _amount);
  }

  function depositAll() external {
    deposit(token.balanceOf(msg.sender));
  }

  /** PRIVATE FUNCTIONS */
  function _deposit(address _user, uint256 _amount) private {
    if (_amount == 0) revert ZERO_AMOUNT();

    token.safeTransferFrom(_user, staker, _amount);
    IStaker(staker).stake(_amount);
    ITokenMinter(minter).mint(_user, _amount);

    emit Deposited(_user, _amount);
  }

  function _isEligibleSender() private view {
    if (msg.sender != tx.origin && whitelist.isWhitelisted(msg.sender) == false) revert UNAUTHORIZED();
  }

  /** OWNER FUNCTIONS */
  function setWhitelist(address _whitelist) external onlyOwner {
    emit WhitelistUpdated(_whitelist, address(whitelist));
    whitelist = IWhitelist(_whitelist);
  }

  /**
    Retrieve stuck funds
   */
  function retrieve(IERC20 _token) external onlyOwner {
    if ((address(this).balance) != 0) {
      Address.sendValue(payable(owner()), address(this).balance);
    }

    _token.transfer(owner(), token.balanceOf(address(this)));
  }

  function setPaused(bool _pauseContract) external onlyOwner {
    if (_pauseContract) {
      _pause();
    } else {
      _unpause();
    }
  }

  event WhitelistUpdated(address _new, address _old);
  event Deposited(address indexed _user, uint256 _amount);

  error ZERO_AMOUNT();
  error UNAUTHORIZED();
}

