// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import { IRdntLpStaker, ITokenMinter } from "./Interfaces.sol";
import { IWhitelist } from "./Whitelist.sol";

contract RdntDepositor is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, PausableUpgradeable {
  using SafeERC20 for IERC20;

  IERC20 public constant dlp = IERC20(0x32dF62dc3aEd2cD6224193052Ce665DC18165841);
  address public constant minter = 0x1605bbDAB3b38d10fA23A7Ed0d0e8F4FEa5bFF59;
  address public constant staker = 0x2A2CAFbB239af9159AEecC34AC25521DBd8B5197;

  IWhitelist public whitelist;
  mapping(address => bool) public handlers;

  uint256 public dlpThreshold;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public virtual initializer {
    __Ownable2Step_init();
    __UUPSUpgradeable_init();
    __Pausable_init();
    _pause();
    dlpThreshold = 35_000 ether;
  }

  /**
   * Deposit asset for plsAsset
   */
  function deposit(uint256 _amount) public whenNotPaused {
    _isEligibleSender();
    _deposit(msg.sender, msg.sender, _amount);
  }

  function depositAll() external {
    deposit(dlp.balanceOf(msg.sender));
  }

  function depositFor(address _user, uint256 _amount) external whenNotPaused {
    if (handlers[msg.sender] == false) revert UNAUTHORIZED();
    _deposit(msg.sender, _user, _amount);
  }

  /** PRIVATE FUNCTIONS */
  function _deposit(address _from, address _user, uint256 _amount) private {
    if (_amount == 0) revert ZERO_AMOUNT();

    dlp.safeTransferFrom(_from, address(this), _amount);
    uint256 _dlpBalance = dlp.balanceOf(address(this));

    if (_dlpBalance > dlpThreshold) {
      dlp.safeTransferFrom(address(this), staker, _dlpBalance);
      IRdntLpStaker(staker).stake(_dlpBalance);
    }
    ITokenMinter(minter).mint(_user, _amount);

    emit Deposited(_user, _amount);
  }

  function _isEligibleSender() private view {
    if (msg.sender != tx.origin && whitelist.isWhitelisted(msg.sender) == false) revert UNAUTHORIZED();
  }

  /** OWNER FUNCTIONS */
  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  function setWhitelist(address _whitelist) external onlyOwner {
    emit WhitelistUpdated(_whitelist, address(whitelist));
    whitelist = IWhitelist(_whitelist);
  }

  function setHandler(address _handler, bool _isActive) external onlyOwner {
    handlers[_handler] = _isActive;
    emit HandlerUpdated(_handler, _isActive);
  }

  function setThreshold(uint256 _threshold) external onlyOwner {
    emit ThresholdUpdated(_threshold);
    dlpThreshold = _threshold;
  }

  function recoverErc20(IERC20 _erc20, uint _amount) external onlyOwner {
    IERC20(_erc20).transfer(owner(), _amount);
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
  event HandlerUpdated(address _address, bool _isActive);
  event ThresholdUpdated(uint256 _threshold);

  error ZERO_AMOUNT();
  error UNAUTHORIZED();
}

