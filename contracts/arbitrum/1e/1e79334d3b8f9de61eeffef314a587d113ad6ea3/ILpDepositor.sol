pragma solidity 0.8.16;

interface ILpDepositor {
    function tokenID() external view returns (uint256);

    function setTokenID(uint256 tokenID) external returns (bool);

    function userBalances(address user, address pool)
        external
        view
        returns (uint256);

    function totalBalances(address pool) external view returns (uint256);

    function transferDeposit(
        address pool,
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function whitelist(address token) external returns (bool);

    function detachGauges(address[] memory gaugeAddresses) external;

    function reattachGauges(address[] memory gaugeAddresses) external;
}

