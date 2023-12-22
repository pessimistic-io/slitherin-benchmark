// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

interface ICollateralToken {
    function getToken() external view returns (address);

    function mintToUser(address recipient, uint256 amount) external;

    function burnFromUser(address recipient, uint256 amount) external;

    function deposit(uint256 amount) external;

    function depositFor(address recipient, uint256 amount) external;

    function withdraw(uint256 amount) external;

    function withdrawEther(uint256 amount) external;
}

