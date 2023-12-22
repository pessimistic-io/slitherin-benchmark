pragma solidity ^0.8.19;

interface ISiloLens {
    function collateralBalanceOfUnderlying(
        address _silo,
        address _asset,
        address _user
    )
    external
    view
    returns (uint256);
}
