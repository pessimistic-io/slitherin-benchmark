// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ILibraryReportStorage} from "./ILibraryReportStorage.sol";

abstract contract LibraryReportStorage is ILibraryReportStorage {
  LibrariesReport internal _librariesReport;

  function getLibrariesReport() public view returns (LibrariesReport memory) {
    return _librariesReport;
  }
}

