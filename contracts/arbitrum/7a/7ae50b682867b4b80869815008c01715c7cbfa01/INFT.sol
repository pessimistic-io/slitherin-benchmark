// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.6.12;

interface INFT {
    function walletOfOwner(address _owner) external view returns (uint256[] memory);
    function MAX_ELEMENTS() external view returns (uint256);
}
