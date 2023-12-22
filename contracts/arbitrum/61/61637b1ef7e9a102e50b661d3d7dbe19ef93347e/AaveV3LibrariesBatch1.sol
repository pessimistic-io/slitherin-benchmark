// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LibraryReportStorage} from "./LibraryReportStorage.sol";
import "./console.sol";
import {Create2Utils} from "./Create2Utils.sol";
import {BorrowLogic} from "./BorrowLogic.sol";
import {BridgeLogic} from "./BridgeLogic.sol";
import {ConfiguratorLogic} from "./ConfiguratorLogic.sol";
import {EModeLogic} from "./EModeLogic.sol";

contract AaveV3LibrariesBatch1 is LibraryReportStorage, Create2Utils {
  constructor(LibrariesReport memory deployedLibraries) {
    _librariesReport = _deployAaveV3Libraries(deployedLibraries);
  }

  function _deployAaveV3Libraries(
    LibrariesReport memory deployedLibraries
  ) internal returns (LibrariesReport memory libReport) {
    bytes32 salt = keccak256('AAVE_V3');
    libReport = deployedLibraries;
    libReport.borrowLogic = _create2Deploy(salt, type(BorrowLogic).creationCode);
    libReport.bridgeLogic = _create2Deploy(salt, type(BridgeLogic).creationCode);
    libReport.configuratorLogic = _create2Deploy(salt, type(ConfiguratorLogic).creationCode);
    libReport.eModeLogic = _create2Deploy(salt, type(EModeLogic).creationCode);
    return libReport;
  }
}

