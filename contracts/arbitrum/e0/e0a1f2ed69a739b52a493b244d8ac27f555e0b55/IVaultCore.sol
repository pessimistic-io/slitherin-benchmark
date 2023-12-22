// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IVaultCore {
    function mintRedeemAllowed() external view returns (bool);
    function allocationAllowed() external view returns (bool);
    function rebaseAllowed() external view returns (bool);
    function swapfeeInAllowed() external view returns (bool);
    function swapfeeOutAllowed() external view returns (bool);
    function oracleAddr() external view returns (address);
    function startBlockHeight() external view returns (uint);
    function chi_alpha() external view returns (uint32);
    function chi_alpha_prec() external view returns (uint64);
    function chi_prec() external view returns (uint64);
    function chiInit() external view returns (uint);
    function chi_beta() external view returns (uint32);
    function chi_beta_prec() external view returns (uint16);
    function chi_gamma() external view returns (uint32);
    function chi_gamma_prec() external view returns (uint16);
    function swapFee_prec() external view returns (uint64);
    function swapFee_p() external view returns (uint32);
    function swapFee_p_prec() external view returns (uint16);
    function swapFee_theta() external view returns (uint32);
    function swapFee_theta_prec() external view returns (uint16);
    function swapFee_a() external view returns (uint32);
    function swapFee_a_prec() external view returns (uint16);
    function swapFee_A() external view returns (uint32);
    function swapFee_A_prec() external view returns (uint16);
    function allocatePercentage_prec() external view returns (uint8);
    function collateralRatio() external view returns (uint);
}

