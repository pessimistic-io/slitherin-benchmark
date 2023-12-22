// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.4;

import "./Ownable.sol";
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
  IStrategy public oracle;                      // oracle is used to get the signal data from strategy script on off-chain.
  address link;                               // ERC677LINK token address
  IManager _manager;
  uint256 public upkeepId;                    
  uint256 public vaultCount;
  mapping (uint256 => address) vaults;
  mapping (address => bool) vaultExist;

  event VaultAdded(address vault);
  event VaultRemoved(address vault);

  modifier onlyManager() {
    require(msg.sender == address(_manager), "!manager");
    _;
  }

  function initialize() public {
    _manager = IManager(msg.sender);
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
      uint256 lookback = vault.lookback();
      bool _signal = IStrategy(vault.strategy()).signal(lookback);
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

  function performUpkeep(bytes calldata performData) external override {
    require(msg.sender == _manager.keeperRegistry(), "not a keeper registry");
    (address vault) = abi.decode(
      performData,
      (address)
    );

    // double check upkeep condition
    uint256 lookback = IPerpetualVault(vault).lookback();
    bool _signal = IStrategy(IPersonalVault(vault).strategy()).signal(lookback);
    require(
      IPerpetualVault(vault).isLong() != _signal || 
      IERC20(IPerpetualVault(vault).hedgeToken()).balanceOf(vault) > 0,
      "invalid condition"
    );
    
    IPersonalVault(vault).run();
  }

  function setUpkeepId(uint256 _upkeepId) external onlyManager {
    upkeepId = _upkeepId;
  }

  //////////////////////////////
  ////    View Functions    ////
  //////////////////////////////

  function manager() external view returns (address) {
    return address(_manager);
  }

}

