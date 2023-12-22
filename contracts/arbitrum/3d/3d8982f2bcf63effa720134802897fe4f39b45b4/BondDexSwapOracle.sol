// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "./ExampleOracleSimple.sol";
import "./BondBaseOracle.sol";


contract BondDexSwapOracle is BondBaseOracle {
    using FullMath for uint256;

    struct DexSwapParams {
        ExampleOracleSimple oracleSimple01;
        ExampleOracleSimple oracleSimple02;
        address tokenIntermediary;
        uint8 decimals; 
    }

    mapping(ERC20 => mapping(ERC20 => DexSwapParams)) public dexSwapParams;


    constructor(address aggregator_, address[] memory auctioneers_)
        BondBaseOracle(aggregator_, auctioneers_)
    {}


    function _currentPrice(ERC20 quoteToken_, ERC20 payoutToken_)
        internal
        view
        override
        returns (uint256)
    {
        DexSwapParams memory params = dexSwapParams[quoteToken_][payoutToken_];

        if (address(params.oracleSimple01) == address(0)) revert BondOracle_InvalidParams();

        if (address(params.oracleSimple02) == address(0)) {
            return
                _validateAndGetPriceSingleSwap(
                    address(payoutToken_),
                    params.oracleSimple01,
                    params.decimals
                );
        } else {
            return
                _validateAndGetPriceDoubleSwap(
                    address(payoutToken_),
                    params.oracleSimple01,
                    params.oracleSimple02,
                    params.tokenIntermediary,
                    params.decimals
                );
        }
    }

    function _validateAndGetPriceSingleSwap(
        address token_,
        ExampleOracleSimple oracleSimple_,
        uint8 decimals_
    ) internal view returns (uint256) {
        address tokenOut = token_ == oracleSimple_.token0() ? oracleSimple_.token1() : oracleSimple_.token0();
        uint256 amountPayoutIn = 1 * 10 ** ERC20(token_).decimals();
        uint256 amountQuoteOut = oracleSimple_.consult(token_, amountPayoutIn);
        return amountQuoteOut.mulDiv(10 ** decimals_, 10 ** ERC20(tokenOut).decimals());
    }

    function _validateAndGetPriceDoubleSwap(
        address token_,
        ExampleOracleSimple oracleSimple01_,
        ExampleOracleSimple oracleSimple02_,
        address tokenIntermediary_,
        uint8 decimals_
    ) internal view returns (uint256) {
        address tokenOut = tokenIntermediary_ == oracleSimple02_.token0() ? oracleSimple02_.token1() : oracleSimple02_.token0();
        uint256 amountPayoutIn = 1 * 10 ** ERC20(token_).decimals();
        uint256 amountInt = oracleSimple01_.consult(token_, amountPayoutIn);
        uint256 amountQuoteOut = oracleSimple02_.consult(tokenIntermediary_, amountInt);
        return amountQuoteOut.mulDiv(10 ** decimals_, 10 ** ERC20(tokenOut).decimals());
    }

    function _decimals(ERC20 quoteToken_, ERC20 payoutToken_)
        internal
        view
        override
        returns (uint8)
    {
        return dexSwapParams[quoteToken_][payoutToken_].decimals;
    }

    function _setPair(
        ERC20 quoteToken_,
        ERC20 payoutToken_,
        bool supported_,
        bytes memory oracleData_
    ) internal override {
        if (supported_) {

            DexSwapParams memory params = abi.decode(oracleData_, (DexSwapParams));

            uint8 quoteDecimals = quoteToken_.decimals();
            uint8 payoutDecimals = payoutToken_.decimals();

            if (
                address(params.oracleSimple01) == address(0) ||
                params.decimals < 6 ||
                params.decimals > 18 ||
                quoteDecimals < 6 ||
                quoteDecimals > 18 ||
                payoutDecimals < 6 ||
                payoutDecimals > 18
            ) revert BondOracle_InvalidParams();

            if (
                address(params.oracleSimple02) != address(0) &&
                params.tokenIntermediary == address(0)
            ) revert BondOracle_InvalidParams();

            if (address(params.oracleSimple01).code.length == 0) revert BondOracle_InvalidParams();

            if (address(params.oracleSimple02) == address(0)) {

                address token0 = params.oracleSimple01.token0();
                address token1 = params.oracleSimple01.token1();
                if (
                    (token0 != address(quoteToken_) && token1 != address(quoteToken_)) ||
                    (token0 != address(payoutToken_) && token1 != address(payoutToken_))
                ) revert BondOracle_InvalidParams();
            } else {

                if (address(params.oracleSimple02).code.length == 0)
                    revert BondOracle_InvalidParams();

                address token0_01 = params.oracleSimple01.token0();
                address token1_01 = params.oracleSimple01.token1();
                address token0_02 = params.oracleSimple02.token0();
                address token1_02 = params.oracleSimple02.token1();

                if (
                    (token0_01 != address(payoutToken_) && token1_01 != address(payoutToken_)) ||
                    (token0_02 != address(quoteToken_) && token1_02 != address(quoteToken_)) 
                ) revert BondOracle_InvalidParams();

                if (
                    (token0_01 != params.tokenIntermediary && token1_01 != params.tokenIntermediary) ||
                    (token0_02 != params.tokenIntermediary && token1_02 != params.tokenIntermediary) 
                ) revert BondOracle_InvalidParams();
            }
            dexSwapParams[quoteToken_][payoutToken_] = params;
        } else {
            delete dexSwapParams[quoteToken_][payoutToken_];
        }
    }
}

