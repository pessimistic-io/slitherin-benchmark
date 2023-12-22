// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./IBinaryVault.sol";
import {BinaryVaultDataType} from "./BinaryVaultDataType.sol";

interface IBinaryVaultFacet is IBinaryVault {
    function setWhitelistMarket(
        address market,
        bool whitelist,
        uint256 exposureBips
    ) external;

    function addLiquidity(
        uint256 tokenId,
        uint256 amount,
        bool isNew
    ) external returns (uint256);

    function mergePositions(uint256[] memory tokenIds) external;

    function requestWithdrawal(uint256 shareAmount, uint256 tokenId) external;

    function executeWithdrawalRequest(uint256 tokenId) external;

    function cancelWithdrawalRequest(uint256 tokenId) external;

    function getSharesOfUser(address user)
        external
        view
        returns (
            uint256 shares,
            uint256 underlyingTokenAmount,
            uint256 netValue,
            uint256 fee
        );

    function getSharesOfToken(uint256 tokenId)
        external
        view
        returns (
            uint256 shares,
            uint256 tokenValue,
            uint256 netValue,
            uint256 fee
        );

    function setConfig(address _config) external;

    function setWithdrawalDelayTime(uint256 _time) external;

    function cancelExpiredWithdrawalRequest(uint256 tokenId) external;

    function getPendingRiskFromBet() external view returns (uint256 riskAmount);

    function withdrawManagementFee(uint256 from, uint256 to) external;

    function getManagementFee() external view returns (uint256 feeAmount);

    function generateTokenURI(uint256 tokenId)
        external
        view
        returns (string memory);

    function config() external view returns (address);

    function underlyingTokenAddress() external view returns (address);

    function shareBalances(uint256) external view returns (uint256);

    function initialInvestments(uint256) external view returns (uint256);

    function recentSnapshots(uint256) external view returns (uint256);

    function withdrawalRequests(uint256)
        external
        view
        returns (BinaryVaultDataType.WithdrawalRequest memory);

    function totalShareSupply() external view returns (uint256);

    function totalDepositedAmount() external view returns (uint256);

    function watermark() external view returns (uint256);

    function pendingWithdrawalTokenAmount() external view returns (uint256);

    function pendingWithdrawalShareAmount() external view returns (uint256);

    function withdrawalDelayTime() external view returns (uint256);

    function isDepositPaused() external view returns (bool);

    function isWhitelistedUser(address user) external view returns (bool);

    function isUseWhitelist() external view returns (bool);

    function enableUseWhitelist(bool value) external;

    function enablePauseDeposit(bool value) external;

    function setWhitelistUser(address user, bool value) external;
}

