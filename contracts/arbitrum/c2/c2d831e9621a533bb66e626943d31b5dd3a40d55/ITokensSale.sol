// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ITokensSale {
    struct UserInfo {
        uint256 paymentAmount;
        bool harvested;
    }
    struct BatchSaleInfo {
        address recipent;
        address paymentToken;
        uint256 price; // wei per token
        uint256 minAmount; // payment token in wei
        uint256 hardCap; // wei
        uint256 start;
        uint256 end;
        uint256 releaseTimestamp;
        uint256 tgeCliff;
        uint256 totalPaymentAmount; // wei
    }

    function tokensVesting() external view returns (address);

    function userInfos(
        uint256 batchNumber,
        address user
    ) external view returns (UserInfo memory);

    function batchSaleInfos(
        uint256 batchNumber
    ) external view returns (BatchSaleInfo memory);
}

