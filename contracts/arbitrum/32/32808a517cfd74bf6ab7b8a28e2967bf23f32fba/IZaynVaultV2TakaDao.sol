// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.5;

interface IZaynVaultV2TakaDao {
    function totalSupply() external view returns (uint256);

    function depositZap(uint256 _amount, uint256 _term) external;

    function withdrawZap(uint256 _shares, uint256 _term) external;

    function want() external pure returns (address);

    function balance() external pure returns (uint256);

    function strategy() external pure returns (address);

    function balanceOf(uint256 term) external returns (uint256);

    function getPricePerFullShare() external view returns (uint256);
}

