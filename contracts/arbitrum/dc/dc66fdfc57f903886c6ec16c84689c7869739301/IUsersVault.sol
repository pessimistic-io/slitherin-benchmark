// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";

import {IBaseVault} from "./IBaseVault.sol";
import {IAdapter} from "./IAdapter.sol";

interface IUsersVault is IBaseVault, IERC20Upgradeable {
    struct UserData {
        uint256 round;
        uint256 pendingDepositAssets;
        uint256 pendingWithdrawShares;
        uint256 unclaimedDepositShares;
        uint256 unclaimedWithdrawAssets;
    }

    function traderWalletAddress() external view returns (address);

    function pendingDepositAssets() external view returns (uint256);

    function pendingWithdrawShares() external view returns (uint256);

    function processedWithdrawAssets() external view returns (uint256);

    function kunjiFeesAssets() external view returns (uint256);

    function userData(address) external view returns (UserData memory);

    function assetsPerShareXRound(uint256) external view returns (uint256);

    function initialize(
        address underlyingTokenAddress,
        address traderWalletAddress,
        address ownerAddress,
        string memory sharesName,
        string memory sharesSymbol
    ) external;

    function collectFees(uint256 amount) external;

    function setAdapterAllowanceOnToken(
        uint256 protocolId,
        address tokenAddress,
        bool revoke
    ) external;

    function userDeposit(uint256 amount) external;

    function withdrawRequest(uint256 sharesAmount) external;

    function rolloverFromTrader() external;

    function executeOnProtocol(
        uint256 protocolId,
        IAdapter.AdapterOperation memory traderOperation,
        uint256 walletRatio
    ) external;

    function getContractValuation() external view returns (uint256);

    function previewShares(address receiver) external view returns (uint256);

    function claim() external;
}

