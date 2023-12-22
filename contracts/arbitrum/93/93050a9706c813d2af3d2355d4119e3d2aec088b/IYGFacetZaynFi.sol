// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.18;

import {LibTermStorage} from "./LibTermStorage.sol";

interface IYGFacetZaynFi {
    function claimAvailableYield(uint termId) external;

    function claimAvailableYield(uint termId, address user) external;

    function toggleOptInYG(uint termId) external;

    function updateYieldProvider(string memory providerString, address providerAddress) external;

    function toggleYieldLock() external returns (bool);
}

