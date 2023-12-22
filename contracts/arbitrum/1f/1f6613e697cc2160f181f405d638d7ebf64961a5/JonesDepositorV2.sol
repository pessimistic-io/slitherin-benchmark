// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./Initializable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./UUPSUpgradeable.sol";
import { IStaker, ITokenMinter } from "./Interfaces.sol";
import { IWhitelist } from "./Whitelist.sol";

contract JonesDepositorV2 is Initializable, Ownable2StepUpgradeable, PausableUpgradeable, UUPSUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  IERC20Upgradeable public constant STAKING_TOKEN = IERC20Upgradeable(0x460c2c075340EbC19Cf4af68E5d83C194E7D21D0);
  address public constant MINTER = 0xe7f6C3c1F0018E4C08aCC52965e5cbfF99e34A44;
  address public constant STAKER = 0x475e8a89aD4aF634663f2632Fff9E47e551f9600;
  IWhitelist public whitelist;
  mapping(address => bool) public isHandler;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public virtual initializer {
    __Ownable2Step_init();
    __Pausable_init();
    __UUPSUpgradeable_init();
    _pause();
  }

  /**
    Deposit asset for plsAsset
   */
  function deposit(uint256 _amount) public whenNotPaused {
    _isEligibleSender();
    _deposit(msg.sender, msg.sender, _amount);
  }

  function depositAll() external {
    deposit(STAKING_TOKEN.balanceOf(msg.sender));
  }

  /** PRIVATE FUNCTIONS */
  function _deposit(address _from, address _user, uint256 _amount) private {
    if (_amount == 0) revert ZERO_AMOUNT();

    STAKING_TOKEN.safeTransferFrom(_from, STAKER, _amount);
    IStaker(STAKER).stake(_amount);
    ITokenMinter(MINTER).mint(_user, _amount);

    emit Deposited(_user, _amount);
  }

  function depositFor(address _user, uint256 _amount) external whenNotPaused {
    if (isHandler[msg.sender] == false) revert UNAUTHORIZED();
    _deposit(msg.sender, _user, _amount);
  }

  function _isEligibleSender() private view {
    if (msg.sender != tx.origin && whitelist.isWhitelisted(msg.sender) == false) revert UNAUTHORIZED();
  }

  /** OWNER FUNCTIONS */
  // solhint-disable-next-line no-empty-blocks
  function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}

  function setWhitelist(address _whitelist) external onlyOwner {
    emit WhitelistUpdated(_whitelist, address(whitelist));
    whitelist = IWhitelist(_whitelist);
  }

  function updaterHandler(address _handler, bool _isActive) external onlyOwner {
    isHandler[_handler] = _isActive;
    emit HandlerUpdated(_handler, _isActive);
  }

  function recoverErc20(IERC20Upgradeable _erc20, uint _amount) external onlyOwner {
    IERC20Upgradeable(_erc20).transfer(owner(), _amount);
  }

  function setPaused(bool _pauseContract) external onlyOwner {
    if (_pauseContract) {
      _pause();
    } else {
      _unpause();
    }
  }

  event WhitelistUpdated(address _new, address _old);
  event HandlerUpdated(address _address, bool _isActive);
  event Deposited(address indexed _user, uint256 _amount);

  error ZERO_AMOUNT();
  error UNAUTHORIZED();
}

