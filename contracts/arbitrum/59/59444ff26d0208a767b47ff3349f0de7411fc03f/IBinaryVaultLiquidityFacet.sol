// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

interface IBinaryVaultLiquidityFacet {
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

    function getMaxHourlyExposure() external view returns (uint256);

    function isFutureBettingAvailable() external view returns (bool);
    function getExposureAmountAt(uint256 endTime)
        external
        view
        returns (uint256 exposureAmount, uint8 direction);
    function getCurrentHourlyExposureAmount() external view returns (uint256);
    function getPendingRiskFromBet() external view returns (uint256 riskAmount);
    function updateExposureAmount() external;
    
    function addLiquidity(
        uint256 tokenId,
        uint256 amount,
        bool isNew
    ) external returns(uint256);

    function mergePositions(
        uint256[] memory tokenIds
    ) external;

    function requestWithdrawal(
        uint256 shareAmount,
        uint256 tokenId
    ) external;

    function executeWithdrawalRequest(
        uint256 tokenId
    ) external;

    function cancelWithdrawalRequest(uint256 tokenId) external;

    function withdrawManagementFee(
        uint256 from,
        uint256 to
    ) external;

    function getManagementFee() external view returns (uint256 feeAmount);
}
