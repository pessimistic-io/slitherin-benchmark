// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IVaultV2.sol";
import {IERC1155} from "./IERC1155.sol";

interface IVaultV2Extended is IVaultV2, IERC1155 {
    function getEpochsLength() external view returns (uint256);

    function epochs(uint256) external view returns (uint256);

    function deposit(uint256 _id, uint256 _assets, address _receiver) external;

    function previewWithdraw(
        uint256 _id,
        uint256 _shares
    ) external view returns (uint256 entitledAssets);

    function withdraw(
        uint256 _id,
        uint256 _shares,
        address _receiver,
        address _owner
    ) external returns (uint256 assets);
}

