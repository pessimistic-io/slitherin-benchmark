//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

/**
 * @author Chef Photons, Vaultka Team serving high quality drinks; drink responsibly.
 * Responsible for our customers not getting intoxicated
 * @notice provided interface for `Water.sol`
 */
// interface IWater {
//     /// @notice supply USDC to the vault
//     /// @param _amount to be leveraged to Bartender (6 decimals)
//     function leverageVault(uint256 _amount) external;

//     /// @notice collect debt from Bartender
//     /// @param _amount to be collected from Bartender (6 decimals)
//     function repayDebt(uint256 _amount) external;

//     function getTotalDebt() external view returns (uint256);

//     function updateTotalDebt(uint256 profit) external returns (uint256);
// }

interface IWater {
    function lend(uint256 _amount) external returns (bool);

    function repayDebt(uint256 leverage, uint256 debtValue) external;

    function getTotalDebt() external view returns (uint256);

    function updateTotalDebt(uint256 profit) external returns (uint256);

    function totalAssets() external view returns (uint256);

    function totalDebt() external view returns (uint256);

    function balanceOfUSDC() external view returns (uint256);
}

