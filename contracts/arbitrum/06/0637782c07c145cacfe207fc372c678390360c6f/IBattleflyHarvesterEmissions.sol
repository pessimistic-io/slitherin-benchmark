// SPDX-License-Identifier: MIT
pragma solidity >0.8.0;

import "./IAtlasMine.sol";

interface IBattleflyHarvesterEmissions {
    struct HarvesterEmission {
        uint256 amount;
        uint256 harvesterMagic;
        uint256 additionalFlywheelMagic;
    }

    function topupHarvesterEmissions(
        uint256 _amount,
        uint256 _harvesterMagic,
        uint256 _additionalFlywheelMagic
    ) external;

    function setVaultHarvesterStake(uint256 _amount, address _vault) external;

    function getClaimableEmission(uint256 _depositId) external view returns (uint256 emission, uint256 fee);

    function getClaimableEmission(address _vault) external view returns (uint256 emission, uint256 fee);

    function claim(uint256 _depositId) external returns (uint256);

    function claim(address _vault) external returns (uint256);

    function claimVault(address _vault) external returns (uint256);

    function getApyAtEpochIn1000(uint64 epoch) external view returns (uint256);

    // ========== Events ==========
    event topupHarvesterMagic(uint256 amount, uint256 harvesterMagic, uint256 additionalFlywheelMagic, uint64 epoch);
    event ClaimHarvesterEmission(address user, uint256 emission, uint256 depositId);
    event ClaimHarvesterEmissionFromVault(address user, uint256 emission, address vault);
}

