// SPDX-License-Identifier: MIT



pragma solidity 0.8.19;

interface Events {
    event AdaptersRegistryAddressSet(address indexed adaptersRegistryAddress);

    event TraderWalletAddressSet(address indexed traderWalletAddress);
    event UserDeposited(
        address indexed caller,
        uint256 assetsAmount,
        uint256 currentRound
    );
    event WithdrawRequest(
        address indexed account,
        uint256 amount,
        uint256 currentRound
    );
    event SharesClaimed(
        uint256 round,
        uint256 shares,
        address caller,
        address receiver
    );
    event AssetsClaimed(
        uint256 round,
        uint256 assets,
        address owner,
        address receiver
    );
    event UsersVaultRolloverExecuted(
        uint256 round,
        uint256 underlyingTokenPerShare,
        uint256 sharesToMint,
        uint256 sharesToBurn,
        int256 overallProfit,
        uint256 unusedFunds
    );

    event VaultAddressSet(address indexed vaultAddress);
    event UnderlyingTokenAddressSet(address indexed underlyingTokenAddress);
    event TraderAddressSet(address indexed traderAddress);
    event ProtocolToUseAdded(uint256 protocolId);
    event ProtocolToUseRemoved(uint256 protocolId);
    event TraderDeposit(
        address indexed account,
        uint256 amount,
        uint256 currentRound
    );
    event OperationExecuted(
        uint256 protocolId,
        uint256 timestamp,
        string target,
        bool replicate,
        uint256 walletRatio
    );
    event TraderWalletRolloverExecuted(
        uint256 timestamp,
        uint256 round,
        int256 traderProfit,
        uint256 unusedFunds
    );
    event NewGmxShortTokens(address collateralToken, address indexToken);
    event TradeTokenAdded(address token);
    event TradeTokenRemoved(address token);
    event EmergencyCloseError(address closedToken, uint256 closedAmount);
}

