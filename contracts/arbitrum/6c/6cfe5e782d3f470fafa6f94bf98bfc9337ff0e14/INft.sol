// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.4;

interface INft {

    event ReferralEarnings(
        address indexed user,
        address indexed to,
        uint256 amount
    );

    struct Settings {
        address payable feeTo;
        address openseaRegistry;
        uint256 fee;
        uint256 refFee;
        uint256 supply;
        uint256 startTime;
        uint256 endTime;
    }


    struct NftInit {
        uint256 startTime;
        uint256 endTime;
        uint256 fee;
        uint256 refFee;
        uint256 supply;
        address owner;
        address makx;
        address payable feeTo;
        string symbol;
        string name;
    }

    function initialize(
        NftInit calldata init,
        address payable _feeDestination,
        uint256 _feePercent
    ) external;

    function updateFees(uint256 fee, address payable feeTo) external;

    function updateSettings(uint256 startTime, uint256 endTime) external;

    function safeMint(address to, uint256 tokenId) external;
    
    function purchase(
        address to,
        uint256 tokenId,
        address ref
    ) external payable;

    function purchaseMany(
        address to,
        uint256[] calldata tokenIds,
        address ref
    ) external payable;
}

