pragma solidity >=0.7.5;

interface IController {
    function admin() external view returns (address);

    function feeCollector() external view returns (address);

    function strategyFeeRate() external view returns (uint256);
}

interface IVault {
    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function UNDERLYING() external view returns (address);

    function emergencyExit() external;

    function shrinkUnderlying() external;

    function collectDustCoin() external;
}

