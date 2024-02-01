// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;
import {IDerivative} from "./IDerivative.sol";
import {ISynthereumFinder} from "./IFinder.sol";
import {ISynthereumPool} from "./IPool.sol";
import {SynthereumPool} from "./Pool.sol";
import {SynthereumInterfaces} from "./implementation_Constants.sol";
import {   IDeploymentSignature } from "./IDeploymentSignature.sol";
import {SynthereumPoolCreator} from "./PoolCreator.sol";

contract SynthereumPoolFactory is SynthereumPoolCreator, IDeploymentSignature {
  address public synthereumFinder;

  bytes4 public override deploymentSignature;

  constructor(address _synthereumFinder) public {
    synthereumFinder = _synthereumFinder;
    deploymentSignature = this.createPool.selector;
  }

  function createPool(
    IDerivative derivative,
    ISynthereumFinder finder,
    uint8 version,
    ISynthereumPool.Roles memory roles,
    bool isContractAllowed,
    uint256 startingCollateralization,
    ISynthereumPool.Fee memory fee
  ) public override returns (SynthereumPool poolDeployed) {
    address deployer =
      ISynthereumFinder(synthereumFinder).getImplementationAddress(
        SynthereumInterfaces.Deployer
      );
    require(msg.sender == deployer, 'Sender must be Synthereum deployer');
    poolDeployed = super.createPool(
      derivative,
      finder,
      version,
      roles,
      isContractAllowed,
      startingCollateralization,
      fee
    );
  }
}

