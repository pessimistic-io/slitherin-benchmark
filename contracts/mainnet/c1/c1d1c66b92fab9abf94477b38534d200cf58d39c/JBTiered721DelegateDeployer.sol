// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./Clones.sol";

import "./IJBTiered721DelegateDeployer.sol";
import "./JBTiered721Delegate.sol";
import "./JB721TieredGovernance.sol";
import "./JB721GlobalGovernance.sol";

/**
  @notice
  Deploys a tier delegate.

  @dev
  Adheres to -
  IJBTiered721DelegateDeployer: General interface for the generic controller methods in this contract that interacts with funding cycles and tokens according to the protocol's rules.
*/
contract JBTiered721DelegateDeployer is IJBTiered721DelegateDeployer {
  error INVALID_GOVERNANCE_TYPE();

  //*********************************************************************//
  // --------------- public immutable stored properties ---------------- //
  //*********************************************************************//

  /** 
    @notice 
    The contract that supports on-chain governance across all tiers. 
  */
  JB721GlobalGovernance public immutable globalGovernance;

  /** 
    @notice 
    The contract that supports on-chain governance per-tier. 
  */
  JB721TieredGovernance public immutable tieredGovernance;

  /** 
    @notice 
    The contract that has no on-chain governance. 
  */
  JBTiered721Delegate public immutable noGovernance;

  //*********************************************************************//
  // -------------------------- constructor ---------------------------- //
  //*********************************************************************//

  constructor(
    JB721GlobalGovernance _globalGovernance,
    JB721TieredGovernance _tieredGovernance,
    JBTiered721Delegate _noGovernance
  ) {
    globalGovernance = _globalGovernance;
    tieredGovernance = _tieredGovernance;
    noGovernance = _noGovernance;
  }

  //*********************************************************************//
  // ---------------------- external transactions ---------------------- //
  //*********************************************************************//

  /** 
    @notice
    Deploys a delegate.

    @param _projectId The ID of the project this contract's functionality applies to.
    @param _deployTiered721DelegateData Data necessary to fulfill the transaction to deploy a delegate.

    @return newDelegate The address of the newly deployed delegate.
  */
  function deployDelegateFor(
    uint256 _projectId,
    JBDeployTiered721DelegateData memory _deployTiered721DelegateData
  ) external override returns (IJBTiered721Delegate newDelegate) {
    // Deploy the governance variant that was requested
    if (_deployTiered721DelegateData.governanceType == JB721GovernanceType.NONE)
      newDelegate = IJBTiered721Delegate(Clones.clone(address(noGovernance)));
    else if (_deployTiered721DelegateData.governanceType == JB721GovernanceType.TIERED)
      newDelegate = IJBTiered721Delegate(Clones.clone(address(tieredGovernance)));
    else if (_deployTiered721DelegateData.governanceType == JB721GovernanceType.GLOBAL)
      newDelegate = IJBTiered721Delegate(Clones.clone(address(globalGovernance)));
    else revert INVALID_GOVERNANCE_TYPE();

    newDelegate.initialize(
      _projectId,
      _deployTiered721DelegateData.directory,
      _deployTiered721DelegateData.name,
      _deployTiered721DelegateData.symbol,
      _deployTiered721DelegateData.fundingCycleStore,
      _deployTiered721DelegateData.baseUri,
      _deployTiered721DelegateData.tokenUriResolver,
      _deployTiered721DelegateData.contractUri,
      _deployTiered721DelegateData.pricing,
      _deployTiered721DelegateData.store,
      _deployTiered721DelegateData.flags
    );

    // Transfer the ownership to the specified address.
    if (_deployTiered721DelegateData.owner != address(0))
      Ownable(address(newDelegate)).transferOwnership(_deployTiered721DelegateData.owner);

    emit DelegateDeployed(_projectId, newDelegate, _deployTiered721DelegateData.governanceType);

    return newDelegate;
  }
}

