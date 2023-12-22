// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IXRam {
    function xRamConvertToNft(
        uint256 _amount
    ) external returns (uint256 veRamTokenId);

    function instantExit(uint256 _amount) external;
}

