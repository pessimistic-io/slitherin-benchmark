// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {VaultDataTypes} from "./VaultDataTypes.sol";

/**
 * @title IVaultBase
 * @author Souq.Finance
 * @notice Interface for VaultBase contract
 */
interface IVaultBase {
    event FeeChanged(VaultDataTypes.VaultFee newFee);
    event VaultDataSet(VaultDataTypes.VaultData newVaultData);

    function setSwapRouter(address _router) external;

    function getHardcap() external view returns (uint256);

    function getUnderlyingTokenAmounts() external view returns (uint256[] memory);

    function getUnderlyingTokens() external view returns (address[] memory);

    function setFee(VaultDataTypes.VaultFee calldata _newFee) external;

    function setVaultData(VaultDataTypes.VaultData calldata _newVaultData) external;
}
