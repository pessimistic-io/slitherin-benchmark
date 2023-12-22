// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IERC20} from "./IERC20.sol";

/// @title Liquidity Book Pair V2 Interface
/// @author Trader Joe
/// @notice Required interface of LBPair contract
interface ILBLegacyPair {
    function tokenX() external view returns (IERC20);

    function tokenY() external view returns (IERC20);

    function getReservesAndId() external view returns (uint256 reserveX, uint256 reserveY, uint256 activeId);

    function swap(bool sentTokenY, address to) external returns (uint256 amountXOut, uint256 amountYOut);

    function findFirstNonEmptyBinId(uint24 id_, bool sentTokenY) external view returns (uint24 id);

    function getBin(uint24 id) external view returns (uint256 reserveX, uint256 reserveY);
}
