/*
    Copyright 2022 Set Labs Inc.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

    SPDX-License-Identifier: Apache License, Version 2.0
*/

pragma solidity 0.6.10;
pragma experimental "ABIEncoderV2";

import { IJasperVault } from "./IJasperVault.sol";
import { IWETH } from "./IWETH.sol";

interface IGMXModule {
  function weth() external view returns(IWETH);

  function increasingPosition(
    IJasperVault _jasperVault,
    address _underlyingToken,
    address _positionToken,
    int256 _underlyingUnits,
    string calldata _integrationName,
    bytes calldata _positionData
  )
  external;
  function decreasingPosition(
    IJasperVault _jasperVault,
    address _underlyingToken,
    address _positionToken,
    int256 _decreasingPositionUnits,
    string calldata _integrationName,
    bytes calldata _positionData
  )
  external;
  function swap(
    IJasperVault _jasperVault,
    address _tokenIn,
    address _tokenOut,
    int256 _underlyingUnits,
    string calldata _integrationName,
    bytes calldata _positionData
  )
  external;
  function creatOrder(
    IJasperVault _jasperVault,
    address _underlyingToken,
    address _indexToken,
    int256 _underlyingUnits,
    string calldata _integrationName,
    bool _isIncreasing,
    bytes calldata _positionData
  )
  external;
  function initialize(IJasperVault _jasperVault) external;
}

