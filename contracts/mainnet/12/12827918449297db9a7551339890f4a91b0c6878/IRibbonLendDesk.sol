// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

/**
 * @title IRibbonLendDesk
 * @author AlloyX
 */
interface IRibbonLendDesk {
  /**
   * @notice Deposit vault USDC to RibbonLend pool master
   * @param _vaultAddress the vault address
   * @param _address the address of pool master
   * @param _amount the amount to deposit
   */
  function provide(
    address _vaultAddress,
    address _address,
    uint256 _amount
  ) external returns (uint256);

  /**
   * @notice Withdraw USDC from RibbonLend pool master
   * @param _vaultAddress the vault address
   * @param _address the address of pool master
   * @param _amount the amount to withdraw in pool master tokens
   */
  function redeem(
    address _vaultAddress,
    address _address,
    uint256 _amount
  ) external returns (uint256);

  /**
   * @notice Get the USDC value of the Clear Pool wallet
   * @param _vaultAddress the vault address of which we calculate the balance
   */
  function getRibbonLendWalletUsdcValue(address _vaultAddress) external view returns (uint256);

  /**
   * @notice Get the USDC value of the Clear Pool wallet on one pool master address
   * @param _vaultAddress the vault address of which we calculate the balance
   * @param _address the address of pool master
   */
  function getRibbonLendUsdcValueOfPoolMaster(address _vaultAddress, address _address) external view returns (uint256);

  /**
   * @notice Get the RibbonLend Pool addresses for the alloyx vault
   * @param _vaultAddress the vault address
   */
  function getRibbonLendVaultAddressesForAlloyxVault(address _vaultAddress) external view returns (address[] memory);

  /**
   * @notice Get the RibbonLend Vault balance for the alloyx vault
   * @param _vaultAddress the address of alloyx vault
   * @param _ribbonLendVault the address of RibbonLend vault
   */
  function getRibbonLendVaultShareForAlloyxVault(address _vaultAddress, address _ribbonLendVault) external view returns (uint256);
}

