// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";

import "./IERC4626.sol";
import { IWhitelist } from "./Whitelist.sol";
import { ITokenMinter } from "./Common.sol";

contract GlpDepositorV2 is Initializable, Ownable2StepUpgradeable, PausableUpgradeable, UUPSUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  uint private constant FEE_DIVISOR = 1e4;

  struct PartnerInfo {
    bool isActive;
    uint32 exitFee; // in bp
    uint32 rebate; // in bp of {exitFee}
  }

  // GMX
  IERC20Upgradeable public constant fsGLP = IERC20Upgradeable(0x1aDDD80E6039594eE970E5872D247bf0414C8903); // balance query
  IERC20Upgradeable public constant sGLP = IERC20Upgradeable(0x2F546AD4eDD93B956C8999Be404cdCAFde3E89AE); // transfers

  // PLUTUS
  address public constant MINTER = 0x530F1CbB2ebD71bec58D351DCD3768148986A467; // plsGLP
  address public constant STAKER = 0xbec7635c7A475CbE081698ea110eF411e40f8dd9;
  address public constant VAULT = 0x5326E71Ff593Ecc2CF7AcaE5Fe57582D6e74CFF1; // plvGLP

  mapping(address => bool) public isHandler;
  mapping(address => bool) private isPauser;
  mapping(address => PartnerInfo) private partners;

  address private exitFeeCollector;
  uint32 public defaultExitFee;
  uint32 public defaultVaultRebate;
  IWhitelist public whitelist;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address _exitFeeCollector, address _whitelist) public virtual initializer {
    __Ownable2Step_init();
    __Pausable_init();
    __UUPSUpgradeable_init();
    exitFeeCollector = _exitFeeCollector;
    whitelist = IWhitelist(_whitelist);

    defaultExitFee = 200; // fee in bp - 2%
    defaultVaultRebate = 2500; // rebate in bp of {exitFee} - 25%
    IERC20(MINTER).approve(VAULT, type(uint).max);
  }

  function vault() public pure returns (address) {
    return VAULT;
  }

  function deposit(uint _amount) public whenNotPaused {
    _isEligibleSender();
    _deposit(msg.sender, msg.sender, _amount);
  }

  function depositFor(address _user, uint _amount) external whenNotPaused {
    if (!isHandler[msg.sender]) revert UNAUTHORIZED();
    _deposit(msg.sender, _user, _amount);
  }

  function redeem(uint _amount) public whenNotPaused {
    PartnerInfo memory partner = partners[msg.sender];

    uint exitFee = partner.isActive ? partner.exitFee : defaultExitFee;
    uint rebate = partner.isActive ? partner.rebate : defaultVaultRebate;

    _redeem(msg.sender, _amount, exitFee, rebate);
  }

  function previewRedeem(
    address _addr,
    uint _shares
  ) external view returns (uint _exitFeeLessRebate, uint _rebateAmount, uint _assetsLessFee) {
    PartnerInfo memory partner = partners[_addr];

    uint exitFee = partner.isActive ? partner.exitFee : defaultExitFee;
    uint rebate = partner.isActive ? partner.rebate : defaultVaultRebate;
    uint assets = IERC4626(VAULT).previewRedeem(_shares);

    uint _exitFee;
    (_exitFee, _assetsLessFee) = _calculateFee(assets, exitFee);
    (_rebateAmount, _exitFeeLessRebate) = _calculateFee(_exitFee, rebate);
  }

  function getFeeBp(address _addr) external view returns (uint _exitFee, uint _rebate) {
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
    redeem(IERC20(VAULT).balanceOf(msg.sender));
  }

  function donate(uint _assets) external {
    _validateHandler();
    sGLP.safeTransferFrom(msg.sender, STAKER, _assets);
    ITokenMinter(MINTER).mint(VAULT, _assets);
  }

  /** PRIVATE FUNCTIONS */
  function _deposit(address _funder, address _user, uint _assets) private {
    if (_assets < 1e4) revert UNDER_MIN_AMOUNT();

    // unstake for _funder, stake in staker
    // requires approval in user for depositor to spend
    sGLP.safeTransferFrom(_funder, STAKER, _assets);

    // mint appropriate plsGLP to depositor
    ITokenMinter(MINTER).mint(address(this), _assets);

    // deposit plsGLP into vault for plvGLP
    // already max approved in constructor
    uint _shares = IERC4626(VAULT).deposit(_assets, _user);
    emit Deposited(_user, _assets, _shares);

    _validateInvariants();
  }

  function _redeem(address _user, uint _shares, uint exitFee, uint rebate) private {
    if (_shares < 1e4) revert UNDER_MIN_AMOUNT();

    // redeem plvGLP for plsGLP to address(this)
    uint _assets = IERC4626(VAULT).redeem(_shares, address(this), _user);

    (uint _exitFee, uint _assetsLessFee) = _calculateFee(_assets, exitFee);
    (uint _rebateAmount, uint _exitFeeLessRebate) = _calculateFee(_exitFee, rebate);

    // burn redeemed plsGLP less rebate
    ITokenMinter(MINTER).burn(address(this), _assets - _rebateAmount);

    // transfer rebate to vault
    IERC20Upgradeable(MINTER).safeTransfer(VAULT, _rebateAmount);

    // requires approval in staker for depositor to spend
    sGLP.safeTransferFrom(STAKER, _user, _assetsLessFee);
    sGLP.safeTransferFrom(STAKER, exitFeeCollector, _exitFeeLessRebate);

    emit Withdrawed(_user, _shares, _assetsLessFee, _rebateAmount, _exitFeeLessRebate);

    _validateInvariants();
  }

  function _calculateFee(uint _totalAmount, uint _feeInBp) private pure returns (uint _fee, uint _amountLessFee) {
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
    if (fsGLP.balanceOf(STAKER) != IERC20(MINTER).balanceOf(VAULT)) revert INVARIANT_VIOLATION();
  }

  function _validateHandler() private view {
    if (!isHandler[msg.sender]) revert UNAUTHORIZED();
  }

  /** PAUSER */
  function setPaused(bool _pauseContract) external {
    if (msg.sender != owner() && !isPauser[msg.sender]) revert UNAUTHORIZED();

    if (_pauseContract) {
      _pause();
    } else {
      _unpause();
    }
  }

  /** OWNER FUNCTIONS */
  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  function setExitFee(uint32 _newFee, uint32 _vaultRebate) external onlyOwner {
    if (_newFee > FEE_DIVISOR || _vaultRebate > FEE_DIVISOR) revert BAD_FEE();

    emit FeeUpdated(_newFee, _vaultRebate);

    defaultExitFee = _newFee;
    defaultVaultRebate = _vaultRebate;
  }

  ///@dev _partnerAddr needs to have an approval for this contract to spend sGLP
  function updatePartner(address _partnerAddr, uint32 _exitFee, uint32 _rebate, bool _isActive) external onlyOwner {
    partners[_partnerAddr] = PartnerInfo({ isActive: _isActive, exitFee: _exitFee, rebate: _rebate });
    emit PartnerUpdated(_partnerAddr, _exitFee, _rebate, _isActive);
  }

  function recoverErc20(IERC20 _erc20, uint _amount) external onlyOwner {
    IERC20(_erc20).transfer(owner(), _amount);
  }

  function setFeeCollector(address _newFeeCollector) external onlyOwner {
    emit FeeCollectorUpdated(_newFeeCollector, exitFeeCollector);
    exitFeeCollector = _newFeeCollector;
  }

  function setHandler(address _handler, bool _isActive) external onlyOwner {
    isHandler[_handler] = _isActive;
  }

  function setWhitelist(address _whitelist) external onlyOwner {
    emit WhitelistUpdated(_whitelist, address(whitelist));
    whitelist = IWhitelist(_whitelist);
  }

  function setPauser(address _pauser, bool _isActive) external onlyOwner {
    isPauser[_pauser] = _isActive;
  }

  event WhitelistUpdated(address _new, address _old);
  event FeeCollectorUpdated(address _new, address _old);
  event FeeUpdated(uint _newFee, uint _vaultRebate);
  event PartnerUpdated(address _partner, uint32 _exitFee, uint32 _rebate, bool _isActive);
  event Deposited(address indexed _user, uint _assets, uint _shares);
  event Withdrawed(address indexed _user, uint _shares, uint _assetsLessFee, uint _vaultRebate, uint _fee);
  event InvariantsViolated(uint _blockNumber, uint _fsGLPSupply, uint _plsGLPSupply, uint _plvGLPSupply);

  error UNDER_MIN_AMOUNT();
  error UNAUTHORIZED();
  error INVARIANT_VIOLATION();
  error BAD_FEE();
}

