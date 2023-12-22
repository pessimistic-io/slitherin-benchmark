// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.16;

interface IGridFirePayment {
    struct BasketItem {
        address artist;
        uint256 amountPaid;
        bytes32 releaseId;
    }

    event Checkout(address indexed buyer, uint256 amount);
    event Claim(address indexed artist, uint256 amount);

    event Purchase(
        address indexed buyer,
        address indexed artist,
        bytes32 releaseId,
        bytes32 userId,
        uint256 amountPaid,
        uint256 artistShare,
        uint256 platformFee
    );

    event Received(address from, uint256 amount);

    receive() external payable;

    function purchase(
        address artist,
        uint256 amountPaid,
        bytes32 releaseId,
        bytes32 userId
    ) external;

    function checkout(BasketItem[] calldata basket, bytes32 userId) external;

    function claim() external;

    function setServiceFee(uint256 newServiceFee) external;

    function getBalance(address artist) external view returns (uint256);

    function getServiceFee() external view returns (uint256);

    function creditBalances(address artist, uint256 amountPaid) external returns (uint256, uint256);

    function transferEditionPayment(
        address buyer,
        address artist,
        uint256 amountPaid
    ) external returns (uint256, uint256);

    function transferPayment(
        address artist,
        uint256 amountPaid,
        bytes32 releaseId,
        bytes32 userId
    ) external;

    function withdraw() external;
}

