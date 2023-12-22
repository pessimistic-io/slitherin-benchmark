// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "./ERC20.sol";

interface IStrategyVault {
    function deployFunds() external;

    function withdrawFunds() external;

    function weightProportion() external view returns (uint16);

    function vaultWeights() external view returns (uint256[] memory);

    function vaultWeights(uint256) external view returns (uint256);

    function threshold() external view returns (uint256);

    function fetchVaultWeights() external view returns (uint256[] memory);

    function asset() external view returns (ERC20 asset);
}

