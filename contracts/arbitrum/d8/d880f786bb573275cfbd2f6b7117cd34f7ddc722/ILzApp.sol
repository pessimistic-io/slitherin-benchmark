// SPDX-License-Identifier: MIT
// Metadrop Contracts (v2.0.0)

pragma solidity 0.8.19;

import {ILayerZeroReceiver} from "./ILayerZeroReceiver.sol";
import {ILayerZeroUserApplicationConfig} from "./ILayerZeroUserApplicationConfig.sol";
import {IErrors} from "./IErrors.sol";

interface ILzApp is
  IErrors,
  ILayerZeroReceiver,
  ILayerZeroUserApplicationConfig
{
  event SetPrecrime(address precrime);
  event SetTrustedRemote(uint16 _remoteChainId, bytes _path);
  event SetTrustedRemoteAddress(uint16 _remoteChainId, bytes _remoteAddress);
  event SetMinDstGas(uint16 _dstChainId, uint16 _type, uint256 _minDstGas);
}

