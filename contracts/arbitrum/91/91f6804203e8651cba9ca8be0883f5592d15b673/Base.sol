pragma solidity 0.8.19;

// 该变量按位存储了多个不同的配置信息，其中每一个bit都对应一种配置
struct ReserveConfigurationMap {
    //bit 0-15: LTV
    //bit 16-31: Liq. threshold
    //bit 32-47: Liq. bonus
    //bit 48-55: Decimals
    //bit 56: Reserve is active
    //bit 57: reserve is frozen
    //bit 58: borrowing is enabled
    //bit 59: stable rate borrowing enabled
    //bit 60-63: reserved
    //bit 64-79: reserve factor
    uint256 data;
}


struct ReserveData {
    //stores the reserve configuration
    ReserveConfigurationMap configuration;
    //the liquidity index. Expressed in ray
    uint128 liquidityIndex;
    //variable borrow index. Expressed in ray
    uint128 variableBorrowIndex;
    //the current supply rate. Expressed in ray
    uint128 currentLiquidityRate;
    //the current variable borrow rate. Expressed in ray
    uint128 currentVariableBorrowRate;
    //the current stable borrow rate. Expressed in ray
    uint128 currentStableBorrowRate;
    uint40 lastUpdateTimestamp;
    //tokens addresses
    address aTokenAddress;
    address stableDebtTokenAddress;
    address variableDebtTokenAddress;
    //address of the interest rate strategy
    address interestRateStrategyAddress;
    //the id of the reserve. Represents the position in the list of the active reserves
    uint8 id;
}

// 这是一个借贷池，提供了多个能够访问借贷池的函数
interface ILendingPool {
    function deposit(address asset,uint256 amount,address onBehalfOf,uint16 referralCode) external;
    function withdraw(address asset,uint256 amount,address to) external returns (uint256);
    function borrow(address asset,uint256 amount,uint256 interestRateMode,uint16 referralCode,address onBehalfOf) external;
    function repay(address asset,uint256 amount,uint256 rateMode,address onBehalfOf) external returns (uint256);
    function getConfiguration(address asset) external view returns (ReserveConfigurationMap memory);
    function getReserveData(address asset) external view returns (ReserveData memory);
}


interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}
// 继承了IERC20接口
interface IRTOKEN is IERC20{
    // 获取 RToken 合约中所应用的基础资产的地址
    // 当前账户同意授权委托给其他账户一定数量的 RToken，将该 RToken 借给其他人时，由代表账户来完成交易。委托可以通过多次授权多个代表来完成，在实际操作中比直接使用 approve 更加灵活和安全。
    function UNDERLYING_ASSET_ADDRESS() external view returns (address);
    function approveDelegation(address delegatee, uint256 amount) external;
}
interface IBalancer{
    function flashLoan(
        address recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}
