// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IFoxifyAffiliation.sol";

interface IFoxifyAffiliationFull is IFoxifyAffiliation {
    function mergeLevelRates() external view returns (MergeLevelRates memory);

    function mergeLevelPermissions() external view returns (MergeLevelPermissions memory);

    function waves(uint256) external view returns (Wave memory);

    function data(uint256) external view returns (NFTData memory);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

