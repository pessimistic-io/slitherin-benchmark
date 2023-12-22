//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

/**
 * @author Chef Photons, Vaultka Team serving high quality drinks; drink responsibly.
 * Responsible for our customers not getting intoxicated
 * @notice provided interface for `Water.sol`
 */
interface IWater {
    /* ##################################################################
                                EVENTS
    ################################################################## */
    
    /// @notice emit an event when user deposit USDC to the vault
    /// @param user the user address who deposit USDC
    /// @param amount the amount of USDC deposited (6 decimals)
    event WaterDeposit(address indexed user, uint256 amount);
    
    /// @notice emit an event when user withdraw USDC from the vault
    /// @param user the user address who withdraw USDC
    /// @param amount the amount of USDC withdrawn (6 decimals)
    event Withdrawal(address indexed user, uint256 amount);

    /// @notice update the address in setting manager
    /// @param params takes the bytes32 params name
    /// @param value takes the address params value
    event SettingManagerAddr(bytes32 params, address value);

    /// @notice update the uint256 in setting manager
    /// @param params takes the bytes32 params name
    /// @param value takes the uint256 params value
    event SettingManagerValue(bytes32 params, uint256 value);

    /// @notice the total amount of loan bartender makes
    /// @param amount total USDC amount to be transferred (6 decimals)
    /// @param timestamp the time that the leverage occured (seconds)
    event LeverageBartender(uint256 amount, uint256 timestamp);

    /// @notice the total amount of debt to be paid from bartender
    /// @param amount total USDC amount to be transferred (6 decimals)
    /// @param totalDebt total debt to be still be paid (6 decimals)
    /// @param timestamp the time that the debt been paid (seconds)
    event LeverageBartenderDebt(uint256 amount, uint256 totalDebt, uint256 timestamp);

    /* ##################################################################
                                ERRORS
    ################################################################## */
    /// @notice access control if can be access by the user
    /// @param admin the default address set
    /// @param sender `msg.sender` who is invoking the function
    error ThrowPermissionDenied(address admin, address sender);

    /// @notice 0x address / null address
    error ThrowZeroAddress();

    /// @notice 0 token is transferred
    error ThrowZeroAmount();

    /// @notice disabling ERC4626 functions
    error ThrowInvalidFunction();

    /// @dev available params: `bartender` and `fee`
    /// @param params takes the byets32 params name
    /// @param value takes the address params value
    error ThrowInvalidParamsAddr(bytes32 params, address value);

    /// @dev available params: `feeBPS and `cap`
    /// @param params takes the bytes32 params name
    /// @param value takes the uint256 params value
    error ThrowInvalidParamsValue(bytes32 params, uint256 value);

    /// @notice invalid contract address provided
    /// @param account address of the contract
    error ThrowInvalidContract(address account);

    /// @notice max deposit / withdraw that a user can make
    /// @dev if the cap is not set, this event will never be emitted (6 decimals)
    /// @param amount the total asset amount to preview (6 decimals)
    error ThrowAssetCap(uint256 amount, uint256 expected);

    /// @notice withdraw more than available USDC supply
    /// @param totalSupply supply of USDC (6 decimals)
    /// @param withdrawAmount amount wants to withdraw (6 decimals)
    error ThrowUnavailableSupply(uint256 totalSupply, uint256 withdrawAmount);

    /* ##################################################################
                                OWNERFUNCTIONS
    ################################################################## */
    /// @notice update the addresses necessary
    /// @param params bytes32 of the value to update
    /// @param value address of bytes32 to update with
    function settingManagerAddr(bytes32 params, address value) external;

    /// @notice update the values necessary
    /// @param params bytes32 of the values to update
    /// @param value uint256 of bytes32 to update with
    function settingManagerValue(bytes32 params, uint256 value) external;

    /* ##################################################################
                                BARTENDER FUNCTIONS
    ################################################################## */
    /// @notice supply USDC to the vault
    /// @param _amount to be leveraged to Bartender (6 decimals)
    function leverageVault(uint256 _amount) external;

    /// @notice collect debt from Bartender
    /// @param _amount to be collected from Bartender (6 decimals)
    function repayDebt(uint256 _amount) external;
    function getTotalDebt() external view returns (uint256);
}

