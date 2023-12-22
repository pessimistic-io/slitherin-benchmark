pragma solidity ^0.8.19;

interface ISiloIncentivesController {
    function getRewardsBalance(
        address[] calldata _assets,
        address _user
    )
    external
    view
    returns (uint256);
}
