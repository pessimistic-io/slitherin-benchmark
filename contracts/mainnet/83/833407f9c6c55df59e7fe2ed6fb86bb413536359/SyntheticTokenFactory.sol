// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;
import {ISynthereumFinder} from "./IFinder.sol";
import {   ISynthereumFactoryVersioning } from "./IFactoryVersioning.sol";
import {   MintableBurnableIERC20 } from "./MintableBurnableIERC20.sol";
import {SynthereumInterfaces} from "./implementation_Constants.sol";
import {   MintableBurnableTokenFactory } from "./MintableBurnableTokenFactory.sol";

contract SynthereumSyntheticTokenFactory is MintableBurnableTokenFactory {
  address public synthereumFinder;

  uint8 public derivativeVersion;

  constructor(address _synthereumFinder, uint8 _derivativeVersion) public {
    synthereumFinder = _synthereumFinder;
    derivativeVersion = _derivativeVersion;
  }

  function createToken(
    string calldata tokenName,
    string calldata tokenSymbol,
    uint8 tokenDecimals
  ) public override returns (MintableBurnableIERC20 newToken) {
    ISynthereumFactoryVersioning factoryVersioning =
      ISynthereumFactoryVersioning(
        ISynthereumFinder(synthereumFinder).getImplementationAddress(
          SynthereumInterfaces.FactoryVersioning
        )
      );
    require(
      msg.sender ==
        factoryVersioning.getDerivativeFactoryVersion(derivativeVersion),
      'Sender must be a Derivative Factory'
    );
    newToken = super.createToken(tokenName, tokenSymbol, tokenDecimals);
  }
}

