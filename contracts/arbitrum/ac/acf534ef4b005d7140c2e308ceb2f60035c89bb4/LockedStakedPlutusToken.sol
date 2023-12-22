// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./IERC20Upgradeable.sol";

interface IStaking {
  function stakeFor(uint112 _amt, address _user) external;

  function unstakeFor(address _user, address _to) external;

  function stakedDetails(address _user) external view returns (uint256);
}

interface IEpochStakingRewardsRollingV2 {
  function claimRewards(address _user, address _to) external;

  function pendingRewards(
    address _user
  ) external view returns (uint256 _pendingPlsDpx, uint256 _pendingPlsJones);
}

contract LockedStakedPlutusToken is
  Initializable,
  ERC20Upgradeable,
  ERC20BurnableUpgradeable,
  OwnableUpgradeable,
  UUPSUpgradeable
{
  IERC20Upgradeable public constant PLS =
    IERC20Upgradeable(0x51318B7D00db7ACc4026C88c3952B66278B6A67F);
  IStaking public constant STAKING = IStaking(0x27Aaa9D562237BF8E024F9b21DE177e20ae50c05);
  address public constant REWARDS = 0xbe68e51f75F34D8BC06D422056af117b8c23fd54;

  address public multisig;

  mapping(address => bool) public isHandler;
  bool public inPrivateTransferMode;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address _multisig) public initializer {
    __ERC20_init('Locked Staked Plutus Token', 'lsPLS');
    __ERC20Burnable_init();
    __Ownable_init();
    __UUPSUpgradeable_init();
    inPrivateTransferMode = true;
    PLS.approve(address(STAKING), type(uint256).max);
    multisig = _multisig;
  }

  function claimRewards() external {
    IEpochStakingRewardsRollingV2(REWARDS).claimRewards(address(this), multisig);
  }

  function pendingRewards() external view returns (uint256, uint256) {
    return IEpochStakingRewardsRollingV2(REWARDS).pendingRewards(address(this));
  }

  function stakedDetails() external view returns (uint256) {
    return STAKING.stakedDetails(address(this));
  }

  /** OWNER */
  function mint(address to, uint256 amount) public onlyOwner {
    PLS.transferFrom(msg.sender, address(this), amount);
    STAKING.stakeFor(uint112(amount), address(this));
    _mint(to, amount);
  }

  function burnFrom(address account, uint256 amount) public override onlyOwner {
    STAKING.unstakeFor(address(this), owner());
    _burn(account, amount);
  }

  function setInPrivateTransferMode(bool _inPrivateTransferMode) external onlyOwner {
    inPrivateTransferMode = _inPrivateTransferMode;
    emit InPrivateTransferMode(_inPrivateTransferMode);
  }

  function updateHandler(address _handler, bool _isActive) external onlyOwner {
    isHandler[_handler] = _isActive;
    emit HandlerUpdated(_handler, _isActive);
  }

  /** INTERNAL */

  function _transfer(address from, address to, uint256 amount) internal override {
    if (isHandler[msg.sender] || !inPrivateTransferMode) {
      super._transfer(from, to, amount);
    } else {
      revert UNAUTHORIZED();
    }
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

  event HandlerUpdated(address indexed _newHandler, bool _isActive);
  event InPrivateTransferMode(bool _isInPrivateTransferMode);

  error UNAUTHORIZED();
}

