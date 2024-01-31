//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./interfaces_ISale.sol";

interface IProject {
    function isManager(uint256 _projectId, address _account) external view returns (bool);
    function getProject(uint256 _projectId) external view returns (ProjectInfo memory);
    function getManager(uint256 _projectId) external view returns (address);
    function getTotalBuyersWaitingDistribution(uint256 _projectId) external view returns (uint256);
    function getTotalSalesNotClose(uint256 _projectId) external view returns (uint256);
    function setTokenAmount(uint256 _projectId, uint256 _amount) external;
    function setTotalBuyersWaitingDistribution(uint256 _projectId, uint256 _total) external;
    function setTotalSalesNotClose(uint256 _projectId, uint256 _total) external;
    function setSoldQuantityToProject(uint256 _projectId, uint256 _quantity) external;
    function end(uint256 _projectId) external;
}

struct ProjectInfo {
    uint256 id;
    bool isCreatedByAdmin;
    bool isInstantPayment;
    bool isSingle;
    bool isFixed;
    address manager;
    address token;
    uint256 amount;
    uint256 minSales;
    uint256 sold;
    uint256 profitShare;
    uint256 saleStart;
    uint256 saleEnd;
    ProjectStatus status;
}

struct InitializeInput {
    address setting;
    address nftChecker;
    address osbFactory;
    uint256 createProjectFee;
    uint256 activeProjectFee;
    uint256 closeLimit;
    uint256 opFundLimit;
    address opFundReceiver;
}

struct ProjectInput {
    address token;
    string tokenName;
    string tokenSymbol;
    string baseUri;
    bool isSingle;
    bool isFixed;
    bool isInstantPayment;
    address royaltyReceiver;
    uint96 royaltyFeeNumerator;
    uint256 minSales;
    uint256 saleStart;
    uint256 saleEnd;
}

enum ProjectStatus {
    INACTIVE,
    STARTED,
    ENDED
}
