// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import "./Math.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

import { StableMath } from "./StableMath.sol";
import { IVault } from "./IVault.sol";
import { IOracle } from "./IOracle.sol";
import { IStrategy } from "./IStrategy.sol";
import "./Helpers.sol";
import "./console.sol";

contract Harvester is OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;
  using StableMath for uint256;

  event SupportedStrategyUpdate(address _address, bool _isSupported);

  mapping(address => bool) public supportedStrategies;

  address public vaultAddress;
  address public primaryStableAddress;

  /**
   * Address of dripper receiving rewards proceeds.
   */
  address public rewardProceedsAddress;

  address public teamAddress;
  uint256 public teamFeeBps;

  /**
   * @dev Initializer to set up initial internal state
   * @param _vaultAddress Address of the Vault
   * @param _primaryStableAddress Address of primaryStable
   */
  function initialize(
    address _vaultAddress,
    address _primaryStableAddress,
    address _rewardProceedsAddress
  ) external initializer {
    require(address(_vaultAddress) != address(0), "Vault Missing");
    require(address(_primaryStableAddress) != address(0), "PS Missing");
    __ReentrancyGuard_init();
    __Ownable_init();
    vaultAddress = _vaultAddress;
    primaryStableAddress = _primaryStableAddress;
    rewardProceedsAddress = _rewardProceedsAddress;
  }

  /***************************************
                 Configuration
    ****************************************/

  /**
   * @dev Throws if called by any address other than the Vault.
   */
  modifier onlyVaultOrOwner() {
    require(
      msg.sender == vaultAddress || msg.sender == owner(),
      "Caller is not the Vault or Owner"
    );
    _;
  }
  modifier onlyVault() {
    require(msg.sender == vaultAddress, "Caller is not the Vault");
    _;
  }

  /**
   * Set the Address receiving rewards proceeds. Dripper
   * @param _rewardProceedsAddress Address of the reward token
   */
  function setRewardsProceedsAddress(
    address _rewardProceedsAddress
  ) external onlyOwner {
    require(
      _rewardProceedsAddress != address(0),
      "Rewards proceeds address should be a non zero address"
    );
    rewardProceedsAddress = _rewardProceedsAddress;
  }

  function setTeam(address _team, uint256 _feeBps) external onlyVaultOrOwner {
    require(_team != address(0), "Team address should be a non zero address");
    require(_feeBps > 0, "Team fee should be greater than zero");
    teamAddress = _team;
    teamFeeBps = _feeBps;
  }

  function getTeam() public view returns (address, uint256) {
    return (teamAddress, teamFeeBps);
  }

  /**
   * @dev Flags a strategy as supported or not supported one
   * @param _strategyAddress Address of the strategy
   * @param _isSupported Bool marking strategy as supported or not supported
   */
  function setSupportedStrategy(
    address _strategyAddress,
    bool _isSupported
  ) external onlyVaultOrOwner {
    supportedStrategies[_strategyAddress] = _isSupported;
    emit SupportedStrategyUpdate(_strategyAddress, _isSupported);
  }

  /***************************************
                    Rewards
    ****************************************/
  /*
   * @dev Collect reward tokens from all strategies and distrubte primaryStable
   *      to teams and dripper accounts/contracts.
   */
  function harvestAndDistribute() external onlyVaultOrOwner nonReentrant {
    _harvest();
    _distribute();
  }

  function harvestAndDistribute(
    address _strategy
  ) external onlyVaultOrOwner nonReentrant {
    _harvest(_strategy);
    _distribute();
  }

  function _distribute() internal {
    if (IERC20(primaryStableAddress).balanceOf(address(this)) > 10) {
      _distributeFees(IERC20(primaryStableAddress).balanceOf(address(this)));
      _distributeProceeds(
        IERC20(primaryStableAddress).balanceOf(address(this))
      );
    }
  }

  function _distributeFees(uint256 _amount) internal {
    require(_amount > 0, "Amount should be greater than zero");
    uint256 teamfees = ((_amount * teamFeeBps) / 100.0) / 100.0;
    IERC20(primaryStableAddress).transfer(teamAddress, teamfees);
  }

  function distributeFees() external onlyOwner {
    _distributeFees(IERC20(primaryStableAddress).balanceOf(address(this)));
  }

  function _distributeProceeds(uint256 _amount) internal {
    require(_amount > 0, "Amount should be greater than zero");
    IERC20(primaryStableAddress).transfer(rewardProceedsAddress, _amount);
  }

  function distributeProceeds() external onlyOwner {
    _distributeProceeds(IERC20(primaryStableAddress).balanceOf(address(this)));
  }

  /**
   * @dev Transfer token to owner. Intended for recovering tokens stuck in
   *      contract, i.e. mistaken sends.
   * @param _asset Address for the asset
   * @param _amount Amount of the asset to transfer
   */
  function transferToken(address _asset, uint256 _amount) external onlyOwner {
    IERC20(_asset).safeTransfer(owner(), _amount);
  }

  /**
   * @dev Collect reward tokens from all strategies
   */
  function harvest() external onlyOwner nonReentrant {
    _harvest();
  }

  /**
   * @dev Collect reward tokens for a specific strategy.
   * @param _strategyAddr Address of the strategy to collect rewards from
   */
  function harvest(address _strategyAddr) external onlyOwner nonReentrant {
    _harvest(_strategyAddr);
  }

  /**
   * @dev Collect reward tokens from all strategies
   */
  function _harvest() internal {
    address[] memory allStrategies = IVault(vaultAddress).getAllStrategies();
    for (uint256 i = 0; i < allStrategies.length; i++) {
      _harvest(allStrategies[i]);
    }
  }

    /**
     * @dev Collect reward tokens from a single strategy and swap them for a
     *      supported stablecoin via Uniswap
     * @param _strategyAddr Address of the strategy to collect rewards from.
     */
    function _harvest(address _strategyAddr) internal {
        require(
            supportedStrategies[_strategyAddr],
            "Not a valid strategy address"
        );

        IStrategy strategy = IStrategy(_strategyAddr);
        strategy.collectRewardTokens();
    }
}

