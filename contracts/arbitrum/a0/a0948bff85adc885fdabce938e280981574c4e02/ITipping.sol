// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.18;

interface ITipping {
    /// @notice Indicates that the {StakingPool} address was changed
    event StakingAddressChanged(address indexed newAddress);
    /// @notice Indicates that the {Odeum} address was changed
    event OdeumAddressChanged(address indexed newAddress);
    /// @notice Indicates that the address to send burnt tokens to was changed
    event BurnAddressChanged(address indexed newAddress);
    /// @notice Indicates that the address to team wallet was changed
    event FundAddressChanged(address indexed newAddress);
    /// @notice Indicates that the burn percentage was changed
    event BurnRateChanged(uint256 indexed newPercentage);
    /// @notice Indicates that the percentage of tokens sent to the
    ///         team wallet was changed
    event FundRateChanged(uint256 indexed newPercentage);
    /// @notice Indicates that the percentage of tokens sent to the
    ///         staking pool was changed
    event RewardRateChanged(uint256 indexed newPercentage);
    /// @notice Indicates that the tranfer amount was split
    ///         among several addresses
    event SplitTransfer(address indexed to, uint256 indexed amount);

    /// @notice Sets the address of the {StakinPool} contract
    /// @param STAKING_VAULT The address of the {StakingPool} contract
    /// @dev Emits the {StakingAddressChanged} event
    function setStakingVaultAddress(address STAKING_VAULT) external;

    /// @notice Sets the address of the {Odeum} contract
    /// @param ODEUM The address of the {Odeum} contract
    /// @dev Emits the {OdeumAddressChanged} event
    function setOdeumAddress(address ODEUM) external;

    /// @notice Sets the address to send burnt tokens to
    /// @dev A zero address by default
    /// @param VAULT_TO_BURN The address to send burnt tokens to
    /// @dev Emits the {BurnAddressChanged} event
    function setVaultToBurnAddress(address VAULT_TO_BURN) external;

    /// @notice Sets the address of the team wallet
    /// @param FUND_VAULT The address of the team wallet
    /// @dev Emits the {FundAddressChanged} event
    function setFundVaultAddress(address FUND_VAULT) external;

    /// @notice Sets the new percentage of tokens to be burnt on each
    ///         transfer (in basis points)
    /// @param burnRate The new percentage of tokens to be burnt on each
    ///        transfer (in basis points)
    /// @dev Emits the {BurnRateChanged} event
    function setBurnRate(uint256 burnRate) external;

    /// @notice Sets the new percentage of tokens to be sent to the team wallet on each
    ///         transfer (in basis points)
    /// @param fundRate The new percentage of tokens to be sent to the team wallet on each
    ///        transfer (in basis points)
    /// @dev Emits the {FundRateChanged} event
    function setFundRate(uint256 fundRate) external;

    /// @notice Sets the new percentage of tokens to be sent to the staking pool on each
    ///         transfer (in basis points)
    /// @param rewardRate The new percentage of tokens to be sent to the staking pool on each
    ///        transfer (in basis points)
    /// @dev Emits the {RewardRateChanged} event
    function setRewardRate(uint256 rewardRate) external;

    /// @notice Transfers the `amount` tokens and splits it among several addresses
    /// @param to The main destination address to transfer tokens to
    /// @param amount The amount of tokens to transfer
    /// @dev Emits the {SplitTransfer} event
    function tip(address to, uint256 amount) external;
}

