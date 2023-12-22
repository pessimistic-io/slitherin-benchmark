// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

/// @title  ISafeVault
/// @author crypt0grapher
/// @notice Safe Yield Vault depositing to the third-party yield farms
interface ISafeVault {

    // @notice deposit USDC to the vault from the sender
    // @param _amount amount of USDC to deposit
    function deposit(uint256 _amount) external;

    // @notice Withdraw USDC from the vault to the receiver from the function caller (msg.sender)
    // @param _user user to send tokens to, withdrawn from the sender
    // @param _amount amount of USDC to withdraw
    function withdraw(address _user, uint256 _amount) external;

    // @notice totalSupply of the vault
    // @return total supply of the vault
    function totalSupply() external view returns (uint256);

}

