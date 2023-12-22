// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMarketReportTypes} from "./IMarketReportTypes.sol";

interface ILibraryReportStorage is IMarketReportTypes {
  function getLibrariesReport() external returns (LibrariesReport memory);
}

