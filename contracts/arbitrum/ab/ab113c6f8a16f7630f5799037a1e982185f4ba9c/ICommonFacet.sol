// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IOracle, IBaseOracle} from "./IOracle.sol";
import "./IPermissionsFacet.sol";
import "./ITokensManagementFacet.sol";

import "./LpToken.sol";

interface ICommonFacet {
    struct Storage {
        bytes vaultTokensSecurityParams;
        bytes allTokensSecurityParams;
        LpToken lpToken;
        IOracle oracle;
        address[] tokens;
        address[] immutableTokens;
        address[] mutableTokens;
    }

    function initializeCommonFacet(
        address[] calldata immutableTokens_,
        address[] calldata mutableTokens_,
        IOracle oracle_,
        string memory name,
        string memory symbol
    ) external;

    function updateSecurityParams(
        IBaseOracle.SecurityParams[] calldata allTokensSecurityParams,
        IBaseOracle.SecurityParams[] calldata vaultTokensSecurityParams
    ) external;

    function updateMutableTokens(address[] calldata newMutableTokens) external;

    function updateOracle(IOracle newOracle) external;

    function tvl() external view returns (uint256);

    function getValueOfTokens(address[] memory, uint256[] memory) external view returns (uint256);

    function tokens() external pure returns (address[] memory, address[] memory, address[] memory);

    function getTokenAmounts() external view returns (address[] memory, uint256[] memory);

    function lpToken() external view returns (LpToken);

    function oracle() external view returns (IOracle);
}

