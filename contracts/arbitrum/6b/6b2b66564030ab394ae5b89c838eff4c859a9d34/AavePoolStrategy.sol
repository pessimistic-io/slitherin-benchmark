pragma solidity ^0.8.19;

import "./IAavePoolStrategy.sol";
import "./IAavePool.sol";
import "./AaveStrategyOracle.sol";

contract AavePoolStrategy is IAavePoolStrategy {
    IAavePool pool;
    AaveStrategyOracle oracle;

    constructor(IAavePool _pool, AaveStrategyOracle _oracle) {
        pool = _pool;
        oracle = _oracle;
    }

    function getBalance(address strategist) external view returns(uint256) {
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = pool.getUserAccountData(strategist);


        return oracle.tokenAmount(totalCollateralBase);
    }
}
