// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;
import {IDerivative} from "./IDerivative.sol";
import {ISynthereumFinder} from "./IFinder.sol";
import {SynthereumTICInterface} from "./ITIC.sol";
import {SynthereumTIC} from "./TIC.sol";
import {SynthereumInterfaces} from "./implementation_Constants.sol";
import {   IDeploymentSignature } from "./IDeploymentSignature.sol";
import {TICCreator} from "./TICCreator.sol";

contract SynthereumTICFactory is TICCreator, IDeploymentSignature {
  address public synthereumFinder;

  bytes4 public override deploymentSignature;

  constructor(address _synthereumFinder) public {
    synthereumFinder = _synthereumFinder;
    deploymentSignature = this.createTIC.selector;
  }

  function createTIC(
    IDerivative derivative,
    ISynthereumFinder finder,
    uint8 version,
    SynthereumTICInterface.Roles memory roles,
    uint256 startingCollateralization,
    SynthereumTICInterface.Fee memory fee
  ) public override returns (SynthereumTIC poolDeployed) {
    address deployer =
      ISynthereumFinder(synthereumFinder).getImplementationAddress(
        SynthereumInterfaces.Deployer
      );
    require(msg.sender == deployer, 'Sender must be Synthereum deployer');
    poolDeployed = super.createTIC(
      derivative,
      finder,
      version,
      roles,
      startingCollateralization,
      fee
    );
  }
}

