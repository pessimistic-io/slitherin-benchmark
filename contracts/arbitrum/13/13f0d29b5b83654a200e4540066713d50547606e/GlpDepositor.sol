// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.9;

import "./Pausable.sol";
import "./IERC20.sol";
import "./IERC4626.sol";
import "./SafeERC20.sol";
import "./OwnableWithRetrieve.sol";
import "./ITokenMinter.sol";
import { IWhitelist } from "./Whitelist.sol";

contract GlpDepositor is OwnableWithRetrieve, Pausable {
  using SafeERC20 for IERC20;

  uint256 private constant FEE_DIVISOR = 1e4;
  IERC20 public constant fsGLP = IERC20(0x1aDDD80E6039594eE970E5872D247bf0414C8903); // balance query
  IERC20 public constant sGLP = IERC20(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE); // transfers

  struct PartnerInfo {
    bool isActive;
    uint32 exitFee; // in bp
    uint32 rebate; // in bp of {exitFee}
  }

  address public immutable minter; // plsGLP
  address public immutable staker;
  address public immutable vault; // plvGLP

  address private exitFeeCollector;
  mapping(address => PartnerInfo) private partners;

  uint32 public defaultExitFee;
  uint32 public defaultVaultRebate;

  IWhitelist public whitelist;

  constructor(
    address _minter,
    address _staker,
    address _vault,
    address _exitFeeCollector,
    address _whitelist
  ) {
    minter = _minter;
    staker = _staker;
    vault = _vault;
    exitFeeCollector = _exitFeeCollector;
    whitelist = IWhitelist(_whitelist);

    defaultExitFee = 200; // fee in bp - 2%
    defaultVaultRebate = 2500; // rebate in bp of {exitFee} - 25%
    IERC20(minter).approve(_vault, type(uint256).max);
  }

  function deposit(uint256 _amount) public whenNotPaused {
    _isEligibleSender();
    _deposit(msg.sender, _amount);
  }

  function redeem(uint256 _amount) public whenNotPaused {
    _isEligibleSender();

    PartnerInfo memory partner = partners[msg.sender];

    uint256 exitFee = partner.isActive ? partner.exitFee : defaultExitFee;
    uint256 rebate = partner.isActive ? partner.rebate : defaultVaultRebate;

    _redeem(msg.sender, _amount, exitFee, rebate);
  }

  function previewRedeem(address _addr, uint256 _shares)
    external
    view
    returns (
      uint256 _exitFeeLessRebate,
      uint256 _rebateAmount,
      uint256 _assetsLessFee
    )
  {
    PartnerInfo memory partner = partners[_addr];
    uint256 exitFee = partner.isActive ? partner.exitFee : defaultExitFee;
    uint256 rebate = partner.isActive ? partner.rebate : defaultVaultRebate;
    uint256 assets = IERC4626(vault).previewRedeem(_shares);

    uint256 _exitFee;
    (_exitFee, _assetsLessFee) = _calculateFee(assets, exitFee);
    (_rebateAmount, _exitFeeLessRebate) = _calculateFee(_exitFee, rebate);
  }

  function getFeeBp(address _addr) external view returns (uint256 _exitFee, uint256 _rebate) {
    PartnerInfo memory partner = partners[_addr];
    _exitFee = partner.isActive ? partner.exitFee : defaultExitFee;
    _rebate = partner.isActive ? partner.rebate : defaultVaultRebate;
  }

  ///@notice Deposit _assets
  function depositAll() external {
    deposit(fsGLP.balanceOf(msg.sender));
  }

  ///@notice Withdraw _shares
  function redeemAll() external {
    redeem(IERC20(vault).balanceOf(msg.sender));
  }

  function donate(uint256 _assets) external {
    sGLP.safeTransferFrom(msg.sender, staker, _assets);
    ITokenMinter(minter).mint(vault, _assets);
  }

  /** PRIVATE FUNCTIONS */
  function _deposit(address _user, uint256 _assets) private {
    if (_assets < 1 ether) revert UNDER_MIN_AMOUNT();

    // unstake for _user, stake in staker
    // requires approval in user for depositor to spend
    sGLP.safeTransferFrom(_user, staker, _assets);

    // mint appropriate plsGLP to depositor
    ITokenMinter(minter).mint(address(this), _assets);

    // deposit plsGLP into vault for plvGLP
    // already max approved in constructor
    uint256 _shares = IERC4626(vault).deposit(_assets, _user);
    emit Deposited(_user, _assets, _shares);

    _validateInvariants();
  }

  function _redeem(
    address _user,
    uint256 _shares,
    uint256 exitFee,
    uint256 rebate
  ) private {
    if (_shares < 1 ether) revert UNDER_MIN_AMOUNT();

    // redeem plvGLP for plsGLP to address(this)
    uint256 _assets = IERC4626(vault).redeem(_shares, address(this), _user);

    (uint256 _exitFee, uint256 _assetsLessFee) = _calculateFee(_assets, exitFee);
    (uint256 _rebateAmount, uint256 _exitFeeLessRebate) = _calculateFee(_exitFee, rebate);

    // burn redeemed plsGLP less rebate
    ITokenMinter(minter).burn(address(this), _assets - _rebateAmount);

    // transfer rebate to vault
    SafeERC20.safeTransfer(IERC20(minter), vault, _rebateAmount);

    // requires approval in staker for depositor to spend
    sGLP.safeTransferFrom(staker, _user, _assetsLessFee);
    sGLP.safeTransferFrom(staker, exitFeeCollector, _exitFeeLessRebate);

    emit Withdrawed(_user, _shares, _assetsLessFee, _rebateAmount, _exitFeeLessRebate);

    _validateInvariants();
  }

  function _calculateFee(uint256 _totalAmount, uint256 _feeInBp)
    private
    pure
    returns (uint256 _fee, uint256 _amountLessFee)
  {
    unchecked {
      _fee = (_totalAmount * _feeInBp) / FEE_DIVISOR;
      _amountLessFee = _totalAmount - _fee;
    }
  }

  function _isEligibleSender() private view {
    if (
      msg.sender != tx.origin && whitelist.isWhitelisted(msg.sender) == false && partners[msg.sender].isActive == false
    ) revert UNAUTHORIZED();
  }

  function _validateInvariants() private view {
    /**
     * Invariants:
     * 1. staker fsGLP balance must always equal plsGLP.totalSupply()
     * 2. plsGLP can only be held by vault
     */
    if (fsGLP.balanceOf(staker) != IERC20(minter).balanceOf(vault)) revert INVARIANT_VIOLATION();
  }

  /** OWNER FUNCTIONS */
  function setExitFee(uint32 _newFee, uint32 _vaultRebate) external onlyOwner {
    if (_newFee > FEE_DIVISOR || _vaultRebate > FEE_DIVISOR) revert BAD_FEE();

    emit FeeUpdated(_newFee, _vaultRebate);

    defaultExitFee = _newFee;
    defaultVaultRebate = _vaultRebate;
  }

  ///@dev _partnerAddr needs to have an approval for this contract to spend sGLP
  function updatePartner(
    address _partnerAddr,
    uint32 _exitFee,
    uint32 _rebate,
    bool _isActive
  ) external onlyOwner {
    partners[_partnerAddr] = PartnerInfo({ isActive: _isActive, exitFee: _exitFee, rebate: _rebate });
    emit PartnerUpdated(_partnerAddr, _exitFee, _rebate, _isActive);
  }

  function setFeeCollector(address _newFeeCollector) external onlyOwner {
    emit FeeCollectorUpdated(_newFeeCollector, exitFeeCollector);
    exitFeeCollector = _newFeeCollector;
  }

  function setWhitelist(address _whitelist) external onlyOwner {
    emit WhitelistUpdated(_whitelist, address(whitelist));
    whitelist = IWhitelist(_whitelist);
  }

  function setPaused(bool _pauseContract) external onlyOwner {
    if (_pauseContract) {
      _pause();
    } else {
      _unpause();
    }
  }

  event WhitelistUpdated(address _new, address _old);
  event FeeCollectorUpdated(address _new, address _old);
  event FeeUpdated(uint256 _newFee, uint256 _vaultRebate);
  event PartnerUpdated(address _partner, uint32 _exitFee, uint32 _rebate, bool _isActive);
  event Deposited(address indexed _user, uint256 _assets, uint256 _shares);
  event Withdrawed(address indexed _user, uint256 _shares, uint256 _assetsLessFee, uint256 _vaultRebate, uint256 _fee);
  event InvariantsViolated(uint256 _blockNumber, uint256 _fsGLPSupply, uint256 _plsGLPSupply, uint256 _plvGLPSupply);

  error UNDER_MIN_AMOUNT();
  error UNAUTHORIZED();
  error INVARIANT_VIOLATION();
  error BAD_FEE();
}

