pragma solidity ^0.5.16;

interface IPresaleTimer {
    function isTierPresalePeriod() external view returns (bool);

    function isPresalePeriod() external view returns (bool);

    function isPresaleFinished() external view returns (bool);

    function isLiquidityEnabled() external view returns (bool);

    function isTierDistributionTime() external view returns (bool);

    function isTierClaimable(uint256 _timestamp) external view returns (bool);
}

