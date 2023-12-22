// SPDX-License-Identifier: MIT



pragma solidity 0.8.19;

interface Errors {
    error ZeroAddress(string target);
    error ZeroAmount();
    error UserNotAllowed();
    error ShareTransferNotAllowed();
    error InvalidTraderWallet();
    error TokenTransferFailed();
    error InvalidRound();
    error InsufficientShares(uint256 unclaimedShareBalance);
    error InsufficientAssets(uint256 unclaimedAssetBalance);
    error InvalidRollover();
    error InvalidAdapter();
    error AdapterOperationFailed(address adapter);
    error ApproveFailed(address caller, address token, uint256 amount);
    error NotEnoughReservedAssets(
        uint256 underlyingContractBalance,
        uint256 reservedAssets
    );
    error TooBigAmount();

    error DoubleSet();
    error InvalidVault();
    error CallerNotAllowed();
    error TraderNotAllowed();
    error InvalidProtocol();
    error ProtocolIdPresent();
    error ProtocolIdNotPresent();
    error UsersVaultOperationFailed();
    error SendToTraderFailed();
    error InvalidToken();
    error TokenPresent();
    error NoUniswapPairWithUnderlyingToken(address token);
    error TooEarly();
}

