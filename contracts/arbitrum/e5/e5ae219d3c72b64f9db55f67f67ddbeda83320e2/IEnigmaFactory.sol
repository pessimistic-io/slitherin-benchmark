// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.19;
//pragma abicoder v2;

interface IEnigmaFactory {
    /// -----------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------
    error EnigaFactory__SameImplementation(address EnigmaImplementation);
    error EnigmaFactory__SameFeeRecipient(address);
    error EnigmaFactory__AddressZero();
    error EnigmaFactory__EnigmaPoolSafetyCheckFailed(address newEnigmaImplementation);
    /// -----------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------

    event EnigmaCreated(address enigmaAddress);
    event EnigmaImplementationSet(address oldEnigmaImplementation, address newEnigmaImplementation);
    event Whitelist(address enigmaAddress, bool isWhitelisted);
    event Blacklist(address enigmaAddress, bool isBlacklisted);
    event FeeRecipientSet(address oldFeeRecipient, address feeRecipient);

    /// -----------------------------------------------------------
    /// Structs
    /// -----------------------------------------------------------
    struct ZappParams {
        uint256 amountIn;
        address inputToken;
        address enigmaPool;
        bool swapForToken1;
        uint256 deadline;
        address token0;
        address token1;
        uint256 amount0OutMin;
        uint256 amount1OutMin;
    }

    /// -----------------------------------------------------------
    /// Functions
    /// -----------------------------------------------------------
    function enigmaTreasury() external returns (address feeRecipient);
}

