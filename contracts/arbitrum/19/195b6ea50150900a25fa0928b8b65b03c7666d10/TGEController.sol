// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./TGEVault.sol";
import "./IController.sol";

contract TGEController is IController {
  address public immutable deployer;
  address public immutable pls;

  address public governance;
  address public proposedGovernance;
  bool public started;
  bool public tokenClaimEnabled;
  TGEVault[] public vaults;

  constructor(address _governance, address _pls) {
    governance = _governance;
    pls = _pls;
    deployer = msg.sender;
    started = false;
    tokenClaimEnabled = false;
  }

  /// @dev Claim from all vaults to msg.sender
  function claimAll() external {
    require(tokenClaimEnabled == true, 'Claim not enabled');

    for (uint256 i = 0; i < vaults.length; i++) {
      if (vaults[i].deposit(msg.sender) > 0 && vaults[i].claimed(msg.sender) == false) {
        vaults[i].claim(msg.sender, msg.sender);
      }
    }
  }

  /** MODIFIERS */
  modifier checkTokenClaimEnabled() {
    require(tokenClaimEnabled == true, 'Claim not enabled');
    _;
  }

  modifier onlyGovernance() {
    require(msg.sender == governance, 'Unauthorized');
    _;
  }

  modifier onlyProposedGovernance() {
    require(msg.sender == proposedGovernance, 'Unauthorized');
    _;
  }

  /// @dev Can only be called by the vault contract when it's deployed
  function addVault(address _vault) external {
    require(tx.origin == deployer && msg.sender == _vault, 'Unauthorized');
    vaults.push(TGEVault(_vault));
  }

  /** VIEWS */
  function getVaultCount() external view returns (uint256) {
    return vaults.length;
  }

  /** GOVERNANCE FUNCTIONS */
  function setStarted(bool _started) public onlyGovernance {
    started = _started;
    emit Started(_started);
  }

  function withdrawToGovernance(TGEVault vault) public onlyGovernance {
    vault.withdrawFunds(governance);
  }

  function setTokenClaimEnabled(bool _enabled) external onlyGovernance {
    tokenClaimEnabled = _enabled;
  }

  function endTGE() external onlyGovernance {
    setStarted(false);

    for (uint256 i = 0; i < vaults.length; i++) {
      withdrawToGovernance(vaults[i]);
    }
  }

  function proposeGovernance(address _proposedGovernanceAddr) external onlyGovernance {
    require(_proposedGovernanceAddr != address(0), 'No Zero');
    proposedGovernance = _proposedGovernanceAddr;
    emit GovernancePropose(_proposedGovernanceAddr);
  }

  function claimGovernance() external onlyProposedGovernance {
    address oldGovernance = governance;
    governance = proposedGovernance;
    proposedGovernance = address(0);
    emit GovernanceChange(oldGovernance, governance);
  }

  event Started(bool);
  event VaultDeployed(address indexed vault, address underlying);
  event GovernancePropose(address indexed newAddr);
  event GovernanceChange(address indexed from, address indexed to);
}

