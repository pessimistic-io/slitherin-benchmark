// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./IERC20Metadata.sol";

interface ISharesFeeStore {
    function getFeePercentage(address shareId) external view returns (uint256);

    function collectShareFees(
        address shareId,
        address recipient,
        uint256 fees,
        bool isBuy,
        bytes calldata feedata
    ) external;

    function onUninstall(address shareId) external;

    function onInstall(address shareId) external;

    function withdrawShareFees(address shareId) external returns (uint256);
}

