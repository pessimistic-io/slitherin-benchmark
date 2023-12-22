// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IVaultGenesis {
    // =============================================================
    //                        Events
    // =============================================================

    event SetVaultManager(address indexed previousVaultManager, address indexed newVaultManager);

    event GovernorTransferred(address indexed previousGovernor, address indexed newGovernor);

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    event FeeRecipientChanged(address newFeeRecipient);

    event DepositFeeChanged(uint256 newDepositFee);

    event WithdrawFeeChanged(uint256 newWithdrawFee);

    event PerformanceFeeChanged(uint256 newWithdrawFee);

    event ProtocolFeeChanged(uint256 newWithdrawFee);

    event AddWhitelisted(address[] addresses);

    event RemoveWhitelisted(address[] addresses);

    // =============================================================
    //                        Errors
    // =============================================================

    error ONLY_MANAGER(); // 0xa2ddd971

    error ONLY_GOVERNOR(); // 0xf61c873f

    error ONLY_GOVERNOR_OR_MANAGER(); // 0xe7974fdc

    error MAX_DEPOSIT_FEE_10000(); // 0x01bbb071

    error MAX_WITHDRAW_FEE_10000(); // 0x8906e3d4

    error MAX_PERFORMANCE_FEE_10000(); // 0x19fe5286

    error MAX_PROTOCOL_FEE_10000(); // 0x02df6fd9

    error TOTAL_RATIO_MUST_10000(); // 0x7414a3f6

    error VAULT_HAS_STARTED(); // 0xa9d1578e

    error VAULT_NOT_STARTED(); // 0xbb626942

    error NOT_ENOUGH_SHARES(); // 0x5be4b761

    error ZERO_AMOUNT_OUT(); // 0xb5489e38

    error INVALID_DATA(); // 0x1c698bde

    error INSUFFICIENT_OUTPUT_AMOUNT(); // 0x27dc822c

    error INSUFFICIENT_OUTPUT_SHARES(); // 0x7ac37e46

    error ZERO_ADDRESS(); // 0x538ba4f9

    error SWAP_ERROR(); // 0xcbe60bba

    error NOT_WHITELISTED(); // 0xbffbc6be

    error WRONG_TOKEN_IN(); // 0xf6b8648c

    error WRONG_TOKEN_OUT(); // 0x5e8f1f5b

    error WRONG_AMOUNT(); // 0xc6ea1a16

    error WRONG_DST(); // 0xcb0b65a6

    error SWAP_METHOD_NOT_IDENTIFIED(); // 0xc257a710
}

