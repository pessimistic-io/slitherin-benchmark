pragma solidity ^0.4.26;

interface IApproveProxy {
    function isAllowedProxy(address _proxy) external view returns (bool);

    function claimTokens(
        address token,
        address who,
        address dest,
        uint256 amount
    ) external;

    function tokenApprove() external view returns (address);
}
