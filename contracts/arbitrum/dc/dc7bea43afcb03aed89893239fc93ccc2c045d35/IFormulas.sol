// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IFormulas {
    function setFactorF(int128 _fFactor) external;

    //betUser - sNumberPresition
    //hv - sNumberPresition
    //option_price - sNumberPresition
    function binary_call(int128 betUser, int128 _hv)
        external
        view
        returns (int128);

    function binary_put(int128 betUser, int128 _hv)
        external
        view
        returns (int128);

    //S, K, _hv, betUser, option_price - sNumberPresition
    function option_touch_call(
        int128 S,
        int128 K,
        int128 _hv,
        int128 betUser
    ) external view returns (int128);

    //S, K, _hv, betUser, option_price - sNumberPresition
    function option_touch_put(
        int128 S,
        int128 K,
        int128 _hv,
        int128 betUser
    ) external view returns (int128);

    //S, K, _hv, betUser, option_price - sNumberPresition
    function option_no_touch_call(
        int128 S,
        int128 K,
        int128 _hv,
        int128 betUser
    ) external view returns (int128);

    //S, K, _hv, betUser, option_price - sNumberPresition
    function option_no_touch_put(
        int128 S,
        int128 K,
        int128 _hv,
        int128 betUser
    ) external view returns (int128);

    //S, KH, KL, _hv, betUser, option_price - sNumberPresition
    function option_double_no_touch(
        int128 S,
        int128 KH,
        int128 KL,
        int128 _hv,
        int128 betUser
    ) external view returns (int128);

    //S, KH, KL, _hv, betUser, option_price - sNumberPresition
    function option_double_touch(
        int128 S,
        int128 KH,
        int128 KL,
        int128 _hv,
        int128 betUser
    ) external view returns (int128);

    //S, K, _hv, betUser, option_price - sNumberPresition
    function option_american_call(
        int128 S,
        int128 K,
        int128 _hv,
        int128 betUser
    ) external view returns (int128);

    //S, K, _hv, betUser, option_price - sNumberPresition
    function option_american_put(
        int128 S,
        int128 K,
        int128 _hv,
        int128 betUser
    ) external view returns (int128);

    //_r1, _r2 - sNumberPresition
    function adj_coef(int128 _r1, int128 _r2)
        external
        view
        returns (int128);

    function americanRisk(
        bool _optionType,
        uint256 _timeOption,
        int128 S,
        int128 K,
        int128 _hv
    ) external view returns (int128);

    function american_worse_price_call(
        int128 S0,
        int128 hv,
        uint256 duration
    ) external pure returns(int128);

    function american_worse_price_put(
        int128 S0,
        int128 hv,
        uint256 duration
    ) external pure returns(int128);

//    function american_price_call_put(
//        int128 S0,
//        int128 hv,
//        uint256 duration
//    ) external pure returns (int128);


    function american_price_call_put(
        int128 S0,
        int128 hv
    ) external pure returns(int128);

    function american_collateral_call_put(
        int128 N_lot,
        int128 S0,
        int128 hv,
        uint256 duration
    ) external pure returns(int128);

    function american_collateral_call_accurate(
        int128 N_lot,
        int128 S0,
        int128 hv,
        uint256 duration
    ) external pure returns(int128);

    function american_collateral_put_accurate(
        int128 N_lot,
        int128 S0,
        int128 hv,
        uint256 duration
    ) external pure returns(int128);

    function turbo_barrier(
        int128 leverage,
        int128 assetPrice,
        bool optionType
    ) external pure returns(int128);

    function turbo_notional(
        int128 barrier,
        int128 assetPrice,
        int128 investment,
        bool optionType
    ) external pure returns(int128);

    /// @dev calculates stake payout increase due to blx stake
    function stakeBlxIncrease(
        uint256 blxAmount,          // blx amount
        int128 blxPrice,            // blx price
        uint256 totalLiquidity,     // total liquidity
        uint256 duration            // lock duration
    ) external view returns (int128);


    /// @dev calculates stake payout increase due to blx burning
    function burnBlxIncrease(
        uint256 blxAmount,          // blx amount
        int128 blxPrice,            // blx price
        uint256 totalLiquidity      // total liquidity
    ) external pure returns (int128);

    function volatilityFactor() external view returns (int128);
}

