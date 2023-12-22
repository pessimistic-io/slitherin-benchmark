// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {IZapDexEnum} from "./IZapDexEnum.sol";

interface IZapValidator is IZapDexEnum {
  function prepareValidationData(
    uint8 _dexType,
    bytes calldata _zapInfo
  ) external view returns (bytes memory validationData);

  function validateData(
    uint8 _dexType,
    bytes calldata _extraData,
    bytes calldata _initialData,
    bytes calldata _zapResults
  ) external view returns (bool isValid);
}

