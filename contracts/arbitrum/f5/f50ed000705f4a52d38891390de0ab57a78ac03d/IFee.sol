//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IFee {
    function setFee(uint256 _fee) external;

    function withdraw(address _assetTokenERC20, uint256 amount) external;

    function getFee() external view returns (uint256);
}

