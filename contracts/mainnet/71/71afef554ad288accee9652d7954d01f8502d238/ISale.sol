//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces_IProject.sol";

interface ISale {
    function getSalesProject(uint256 projectId) external view returns (SaleInfo[] memory);
    function getSaleIdsOfProject(uint256 _projectId) external view returns (uint256[] memory);
    function getBuyers(uint256 _saleId) external view returns (address[] memory);
    function setCloseSale(uint256 _saleId) external;
    function setAmountSale(uint256 _saleId, uint256 _amount) external;
    function close(uint256 closeLimit, ProjectInfo memory _project, SaleInfo memory _sale, uint256 _totalBuyersWaitingClose, uint256 _totalCloseSale, bool _isGive) external returns (uint256, uint256);
    function creates(address _caller, bool _isCreateNewToken, bool _isSetRoyalty, ProjectInfo memory _projectInfo, SaleInput[] memory _saleInputs) external returns(uint256);
    function getSaleById(uint256 _saleId) external view returns (SaleInfo memory);
}

struct SaleInfo {
    uint256 id;
    uint256 projectId;
    address token;
    uint256 tokenId;
    uint256 fixedPrice;
    uint256 dutchMaxPrice;
    uint256 dutchMinPrice;
    uint256 priceDecrementAmt;
    uint256 amount;
    bool isSoldOut;
    bool isClose;
}

struct Bill {
    uint256 saleId;
    address account;
    address royaltyReceiver;
    uint256 royaltyFee;
    uint256 superAdminFee;
    uint256 sellerFee;
    uint256 amount;
}

struct SaleInput {
    uint256 tokenId;
    uint256 amount;
    address royaltyReceiver;
    uint96  royaltyFeeNumerator;
    uint256 fixedPrice;
    uint256 maxPrice;
    uint256 minPrice;
    uint256 priceDecrementAmt;
}
