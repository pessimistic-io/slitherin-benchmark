// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./AutomationCompatible.sol";
import "./IStrategy.sol";
import "./IManager.sol";
import "./IPersonalVault.sol";

/**
 * @notice
 *  This is a keeper contract that uses chainlink automation to check signal and trigger actions
 *   based on that signal data
 */
contract Keeper is AutomationCompatibleInterface {
  IManager public _manager;
  address public owner;
  uint256 public upkeepId;                    
  uint256 public vaultCount;
  uint256 public upkeepDelay;
  uint256 public lastTimestamp;
  mapping (uint256 => address) public vaults;
  mapping (address => bool) public vaultExist;
  bool public paused;

  event VaultAdded(address vault);
  event VaultRemoved(address vault);

  modifier onlyManager() {
    require(msg.sender == address(_manager), "!manager");
    _;
  }

  modifier onlyOwner() {
    require(msg.sender == owner, "!owner");
    _;
  }

  function initialize(address _owner) public {
    require(_owner != address(0), "zero address");
    _manager = IManager(msg.sender);
    owner = _owner;
    upkeepDelay = 60 * 60;    // 1 hour
  }

  function addVault(address _vault) external onlyManager {
    require(_vault != address(0), "zero address");
    require(vaultExist[_vault] == false, "already exist");
    require(vaultCount < _manager.maxVaultsPerUser(), "exceed maximum");
    vaults[vaultCount] = _vault;
    vaultCount = vaultCount + 1;
    vaultExist[_vault] = true;

    emit VaultAdded(_vault);
  }

  function removeVault(address _vault) external onlyManager {
    require(_vault != address(0), "zero address");
    require(vaultExist[_vault] == true, "not exist");
    for (uint8 i = 0; i < vaultCount; i++) {
      if (vaults[i] == _vault) {
        vaults[i] = vaults[vaultCount];
        vaultExist[_vault] = false;
        delete vaults[vaultCount];
        vaultCount = vaultCount - 1;
        break;
      }
    }

    emit VaultRemoved(_vault);
  }

  function checkUpkeep(bytes calldata) external view override returns (bool upkeepNeeded, bytes memory performData) {
    for (uint256 i = 0; i < vaultCount; i++) {
      IPerpetualVault vault = IPerpetualVault(vaults[i]);
      if (vault.isNextAction() == true) {
        upkeepNeeded = true;
        performData = abi.encode(address(vault));
      } else {
        address tradeToken = vault.indexToken();
        uint256 lookback = vault.lookback();
        bool _signal = IStrategy(vault.strategy()).getSignal(tradeToken, lookback);
        if (vault.isLong() == _signal) {
          IERC20 hedgeToken = IERC20(vault.hedgeToken());
          if (hedgeToken.balanceOf(address(vault)) > 0) {
            upkeepNeeded = true;
            performData = abi.encode(address(vault));
          } else {
            upkeepNeeded = false;
          }
        } else {
          upkeepNeeded = true;
          performData = abi.encode(address(vault));
        }
      }
    }
  }

  function performUpkeep(bytes calldata performData) external override {
    require(msg.sender == _manager.keeperRegistry(), "not a keeper registry");
    require(paused == false, "paused");
    (address vault) = abi.decode(
      performData,
      (address)
    );
    if (IPerpetualVault(vault).isNextAction() == true) {
      IPerpetualVault(vault).run();
    } else {
      require(block.timestamp - lastTimestamp >= upkeepDelay, "delay");

      // double check upkeep condition
      address tradeToken = IPerpetualVault(vault).indexToken();
      uint256 lookback = IPerpetualVault(vault).lookback();
      bool _signal = IStrategy(IPersonalVault(vault).strategy()).getSignal(tradeToken, lookback);
      require(
        IPerpetualVault(vault).isLong() != _signal || 
        IERC20(IPerpetualVault(vault).hedgeToken()).balanceOf(vault) > 0,
        "invalid condition"
      );
      IPersonalVault(vault).run();
    }
    
    lastTimestamp = block.timestamp;
  }

  function pauseUpkeep(bool _paused) external onlyOwner {
    paused = _paused;
  }

  function setUpkeepId(uint256 _upkeepId) external onlyManager {
    upkeepId = _upkeepId;
  }

  function setUpkeepDelay(uint256 _upkeepDelay) external onlyOwner {
    upkeepDelay = _upkeepDelay;
  }

  //////////////////////////////
  ////    View Functions    ////
  //////////////////////////////

  function manager() external view returns (address) {
    return address(_manager);
  }

  function delayed() external view returns (bool) {
    return block.timestamp - lastTimestamp <= upkeepDelay;
  }

}

