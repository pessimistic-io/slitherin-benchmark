// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;

interface IIRMRouter {
    function setBorrowRate(
        address loanAsset,
        uint256 loanAssetChainId
    ) external /* onlyMaster() */ returns (uint256 rate);

    function borrowInterestRatePerBlock(
        address loanAsset,
        uint256 loanAssetChainId
    ) external view returns (uint256);

    function borrowInterestRateDecimals(
        address loanAsset,
        uint256 loanAssetChainId
    ) external view returns (uint8);
}

