// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./IERC20Metadata.sol";

interface IFeeWithdraw {
    function withdrawProtocolFees() external returns (uint256);

    function withdrawShareFees(address shareId) external returns (uint256);
}

