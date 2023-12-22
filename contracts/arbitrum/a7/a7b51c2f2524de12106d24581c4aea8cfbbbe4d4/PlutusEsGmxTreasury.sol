// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./IERC20Upgradeable.sol";

interface IRewardRouterV2 {
  function stakeGmx(uint256 _amount) external;

  function unstakeGmx(uint256 _amount) external;

  function stakeEsGmx(uint256 _amount) external;

  function unstakeEsGmx(uint256 _amount) external;

  function handleRewards(
    bool _shouldClaimGmx,
    bool _shouldStakeGmx,
    bool _shouldClaimEsGmx,
    bool _shouldStakeEsGmx,
    bool _shouldStakeMultiplierPoints,
    bool _shouldClaimWeth,
    bool _shouldConvertWethToEth
  ) external;
}

contract PlutusEsGmxTreasury is Initializable, OwnableUpgradeable, UUPSUpgradeable {
  IRewardRouterV2 public constant REWARD_ROUTER =
    IRewardRouterV2(0xA906F338CB21815cBc4Bc87ace9e68c87eF8d8F1);
  IERC20Upgradeable public constant WETH =
    IERC20Upgradeable(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  address public constant GOV = 0xa5c1c5a67Ba16430547FEA9D608Ef81119bE1876;

  mapping(address => bool) public isHandler;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __Ownable_init();
    __UUPSUpgradeable_init();
    isHandler[msg.sender] = true;
  }

  modifier onlyHandler() {
    require(isHandler[msg.sender], 'Unauthorized');
    _;
  }

  function stakeEsGmx(uint256 _amount) external onlyHandler {
    REWARD_ROUTER.stakeEsGmx(_amount);
  }

  function stakeGmx(uint256 _amount) external onlyHandler {
    REWARD_ROUTER.stakeGmx(_amount);
  }

  function unstakeEsGmx(uint256 _amount) external onlyHandler {
    REWARD_ROUTER.unstakeEsGmx(_amount);
  }

  function harvestRewards() external onlyHandler {
    REWARD_ROUTER.handleRewards(true, false, true, false, true, true, false);
  }

  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

  function updateHandler(address _handler, bool _isActive) external onlyOwner {
    isHandler[_handler] = _isActive;
  }

  function approveSpend(address _spender, address _token) external onlyOwner {
    IERC20Upgradeable(_token).approve(_spender, type(uint256).max);
  }

  function retrieve(IERC20Upgradeable _token) external onlyOwner {
    _token.transfer(owner(), _token.balanceOf(address(this)));
  }
}

