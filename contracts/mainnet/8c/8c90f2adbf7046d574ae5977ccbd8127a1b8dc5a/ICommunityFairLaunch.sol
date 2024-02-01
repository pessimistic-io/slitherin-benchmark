pragma solidity ^0.8.0;

interface ICommunityFairLaunch {
    function buy(address _referrer) external payable;

    function endSale() external;

    function finalizeSale() external;

    function getUserAllocation(address _investor) external view returns (uint256);

    function getClaimableAmount(address _investor) external view returns (uint256);

    function claim() external;
}

