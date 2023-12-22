pragma solidity >0.8.0;

interface IArkenRouter {
    function WETH() external view returns (address);

    function factory() external view returns (address);

    function factoryLongTerm() external view returns (address);

    function rewarder() external view returns (address);

    struct AddLiquidityData {
        address tokenA;
        address tokenB;
        uint256 amountADesired;
        uint256 amountBDesired;
        uint256 amountAMin;
        uint256 amountBMin;
        address to;
    }

    struct AddLiquiditySingleData {
        address tokenIn;
        uint256 amountIn;
        address tokenA;
        address tokenB;
        uint256 amountAMin;
        uint256 amountBMin;
        address to;
    }

    struct RemoveLiquidityData {
        address tokenA;
        address tokenB;
        uint256 amountAMin;
        uint256 amountBMin;
        address to;
    }

    // Short Term
    function addLiquidity(
        AddLiquidityData calldata data,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function addLiquiditySingle(
        AddLiquiditySingleData calldata data,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function removeLiquidity(
        RemoveLiquidityData calldata data,
        uint256 liquidity,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquiditySingle(
        RemoveLiquidityData calldata data,
        address tokenOut,
        uint256 liquidity,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    // Long Term
    struct AddLongTermInputData {
        uint256 lockTime;
        bytes rewardData;
    }

    struct AddLongTermOutputData {
        uint256 amountA;
        uint256 amountB;
        uint256 liquidity;
        uint256 positionTokenId;
    }

    function addLiquidityLongTerm(
        AddLiquidityData calldata addData,
        AddLongTermInputData calldata longtermData,
        uint256 deadline
    ) external returns (AddLongTermOutputData memory outputData);

    function addLiquidityLongTermSingle(
        AddLiquiditySingleData calldata addData,
        AddLongTermInputData calldata longtermData,
        uint256 deadline
    ) external returns (AddLongTermOutputData memory outputData);

    function removeLiquidityLongTerm(
        RemoveLiquidityData calldata data,
        uint256 positionTokenId,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityLongTermSingle(
        RemoveLiquidityData calldata data,
        address tokenOut,
        uint256 positionTokenId,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
}

