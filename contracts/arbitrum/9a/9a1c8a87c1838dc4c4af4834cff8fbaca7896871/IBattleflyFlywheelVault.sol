//SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0;

interface IBattleflyFlywheelVault {
    function getStakeAmount(address user) external view returns (uint256, uint256);

    function stakeableAmountPerV1() external view returns (uint256);

    function stakeableAmountPerV2() external view returns (uint256);

    function stakeableAmountPerFounder(address vault) external view returns (uint256);
}

