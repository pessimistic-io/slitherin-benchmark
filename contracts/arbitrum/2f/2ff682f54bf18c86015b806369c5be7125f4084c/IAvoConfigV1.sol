// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

interface IAvoConfigV1 {
    struct AvocadoMultisigConfig {
        uint256 authorizedMinFee;
        uint256 authorizedMaxFee;
        address authorizedFeeCollector;
    }

    struct AvoDepositManagerConfig {
        address depositToken;
    }

    struct AvoSignersListConfig {
        bool trackInStorage;
    }

    /// @notice config for AvocadoMultisig
    function avocadoMultisigConfig() external view returns (AvocadoMultisigConfig memory);

    /// @notice config for AvoDepositManager
    function avoDepositManagerConfig() external view returns (AvoDepositManagerConfig memory);

    /// @notice config for AvoSignersList
    function avoSignersListConfig() external view returns (AvoSignersListConfig memory);
}

