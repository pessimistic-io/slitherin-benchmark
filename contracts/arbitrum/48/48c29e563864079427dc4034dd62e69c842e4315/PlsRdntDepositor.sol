// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.20;

import "./IERC20.sol";
import "./IERC4626.sol";
import "./SafeERC20.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";

import { IRdntLpStaker } from "./v2_Interfaces.sol";
import { IWhitelist } from "./Whitelist.sol";
import { IInvariant } from "./Invariant.sol";
import { IErrors, ITokenMinter } from "./Common.sol";

interface IPlsRdntDepositor is IErrors {
  function dlpThresholdBalance() external view returns (uint128);

  event WhitelistUpdated(address _new, address _old);
  event Deposited(address indexed _user, uint _assets, uint _shares);
  event HandlerUpdated(address _address, bool _isActive);
  event CompounderUpdated(address _newCompounder, address _oldCompounder);
  event ThresholdUpdated(uint _threshold);
  event Compounded(uint _amount);

  error ZERO_AMOUNT();
}

contract PlsRdntDepositor is
  IPlsRdntDepositor,
  Initializable,
  Ownable2StepUpgradeable,
  UUPSUpgradeable,
  PausableUpgradeable
{
  using SafeERC20 for IERC20;

  IERC20 public constant dlp = IERC20(0x32dF62dc3aEd2cD6224193052Ce665DC18165841);
  address public constant staker = 0x2A2CAFbB239af9159AEecC34AC25521DBd8B5197;
  address public vdlp;
  address public plsRdnt;

  IWhitelist public whitelist;
  IInvariant public invariant;

  mapping(address => bool) public handlers;
  address public compounder;

  uint128 public dlpThreshold;
  uint128 public dlpThresholdBalance;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address _vdlp,
    address _plsRdnt,
    IInvariant _invariant,
    uint128 _threshold
  ) public virtual initializer {
    __Ownable2Step_init();
    __Ownable_init(msg.sender);

    __Pausable_init();
    __UUPSUpgradeable_init();

    vdlp = _vdlp;
    plsRdnt = _plsRdnt;
    invariant = _invariant;

    IERC20(_vdlp).approve(_plsRdnt, type(uint).max);

    _pause();
    dlpThreshold = _threshold;
  }

  function deposit(uint _amount) public {
    _isEligibleSender();
    _deposit(msg.sender, msg.sender, _amount);
  }

  function depositAll() external {
    deposit(dlp.balanceOf(msg.sender));
  }

  function compound(uint _amount) external {
    if (msg.sender != compounder) revert UNAUTHORIZED();

    _dlpTransferFrom(msg.sender, _amount);
    _stakeIfAboveThreshold();

    ITokenMinter(vdlp).mint(plsRdnt, _amount);
    emit Compounded(_amount);

    if (address(invariant) != address(0)) {
      invariant.checkHold();
    }
  }

  function depositFor(address _user, uint _amount) external {
    if (handlers[msg.sender] == false) revert UNAUTHORIZED();
    _deposit(msg.sender, _user, _amount);
  }

  /** PRIVATE FUNCTIONS */
  function _stakeIfAboveThreshold() private {
    if (dlpThresholdBalance > dlpThreshold) {
      dlp.safeTransfer(staker, dlpThresholdBalance);
      IRdntLpStaker(staker).stake(dlpThresholdBalance);
      dlpThresholdBalance = 0;
    }
  }

  function _dlpTransferFrom(address _from, uint _amount) private {
    if (_amount == 0) revert ZERO_AMOUNT();

    dlp.safeTransferFrom(_from, address(this), _amount);

    if (_amount + dlpThresholdBalance > type(uint128).max) revert FAILED('PlsRdntDepositor');

    unchecked {
      dlpThresholdBalance += uint128(_amount);
    }
  }

  function _deposit(address _from, address _user, uint _amount) private whenNotPaused {
    _dlpTransferFrom(_from, _amount);
    _stakeIfAboveThreshold();

    ITokenMinter(vdlp).mint(address(this), _amount);
    uint _shares = IERC4626(plsRdnt).deposit(_amount, _user);
    emit Deposited(_user, _amount, _shares);

    if (address(invariant) != address(0)) {
      invariant.checkHold();
    }
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

  function updateHandler(address _handler, bool _isActive) external onlyOwner {
    handlers[_handler] = _isActive;
    emit HandlerUpdated(_handler, _isActive);
  }

  function setCompounder(address _newCompounder) external onlyOwner {
    emit CompounderUpdated(_newCompounder, compounder);
    compounder = _newCompounder;
  }

  function setThreshold(uint128 _threshold) external onlyOwner {
    dlpThreshold = _threshold;
    emit ThresholdUpdated(_threshold);
  }

  function setInvariant(IInvariant _newInvariant) external onlyOwner {
    invariant = _newInvariant;
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
}

