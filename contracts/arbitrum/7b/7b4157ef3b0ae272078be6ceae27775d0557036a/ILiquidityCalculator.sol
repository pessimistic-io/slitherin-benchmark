pragma solidity >= 0.8.0;

interface ILiquidityCalculator {
    function getTrancheValue(address _tranche, bool _max) external view returns (uint256);

    function getPoolValue(bool _max) external view returns (uint256 sum);

    function calcSwapFee(address _token, uint256 _tokenPrice, uint256 _valueChange, bool _isSwapIn)
        external
        view
        returns (uint256);

    function calcAddRemoveLiquidityFee(address _token, uint256 _tokenPrice, uint256 _valueChange, bool _isAdd)
        external
        view
        returns (uint256);

    function calcAddLiquidity(address _tranche, address _token, uint256 _amountIn)
        external
        view
        returns (uint256 outLpAmount, uint256 feeAmount);

    function calcRemoveLiquidity(address _tranche, address _tokenOut, uint256 _lpAmount)
        external
        view
        returns (uint256 outAmountAfterFee, uint256 feeAmount);

    function calcSwapOutput(address _tokenIn, address _tokenOut, uint256 _amountIn)
        external
        view
        returns (uint256 amountOutAfterFee, uint256 feeAmount, uint256 priceIn, uint256 priceOut);

    // ========= Events ===========
    event AddRemoveLiquidityFeeSet(uint256 value);
    event SwapFeeSet(
        uint256 baseSwapFee, uint256 taxBasisPoint, uint256 stableCoinBaseSwapFee, uint256 stableCoinTaxBasisPoint
    );

    // ========= Errors ==========
    error InvalidAddress();
    error ValueTooHigh(uint256 value);
}

