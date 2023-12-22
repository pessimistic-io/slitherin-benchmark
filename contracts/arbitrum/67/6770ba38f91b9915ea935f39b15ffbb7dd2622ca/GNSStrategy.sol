// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {BaseStrategy, StrategyParams, VaultAPI} from "./BaseStrategy.sol";
import {ERC20, IERC20} from "./ERC20.sol";
import {Math} from "./Math.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {OracleLibrary} from "./OracleLibrary.sol";

import "./IV3SwapRouter.sol";
import "./IGNSVault.sol";

import "./Utils.sol";

contract GNSStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    address internal constant GNS = 0x18c11FD286C5EC11c3b683Caa813B77f5163A122;
    address internal constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address internal constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    address internal constant GNS_VAULT =
        0x6B8D3C08072a020aC065c467ce922e3A36D3F9d6;
    address internal constant UNISWAP_V3_ROUTER =
        0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

    address internal constant ETH_USDC_UNI_V3_POOL =
        0xC31E54c7a869B9FcBEcc14363CF510d1c41fa443;
    address internal constant GNS_ETH_UNI_V3_POOL =
        0xC91B7b39BBB2c733f0e7459348FD0c80259c8471;
    address internal constant DAI_USDC_UNI_V3_POOL =
        0xF0428617433652c9dc6D1093A42AdFbF30D29f74;

    uint24 internal constant ETH_USDC_UNI_FEE = 500;
    uint24 internal constant GNS_ETH_UNI_FEE = 3000;
    uint24 internal constant DAI_USDC_UNI_FEE = 100;

    uint32 internal constant TWAP_RANGE_SECS = 1800;
    uint32 internal constant DAI_USDC_TWAP_RANGE_SECS = 1200;

    uint256 public slippage = 9900; // 1%

    constructor(address _vault) BaseStrategy(_vault) {
        want.approve(UNISWAP_V3_ROUTER, type(uint256).max);
        ERC20(DAI).approve(UNISWAP_V3_ROUTER, type(uint256).max);
        ERC20(GNS).approve(UNISWAP_V3_ROUTER, type(uint256).max);
        ERC20(GNS).approve(GNS_VAULT, type(uint256).max);
    }

    function setSlippage(uint256 _slippage) external onlyStrategist {
        require(_slippage < 10_000, "!_slippage");
        slippage = _slippage;
    }

    function name() external pure override returns (string memory) {
        return "StrategyGNS";
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfDai() public view returns (uint256) {
        return IERC20(DAI).balanceOf(address(this));
    }

    function balanceOfWeth() public view returns (uint256) {
        return IERC20(WETH).balanceOf(address(this));
    }

    function balanceOfGns() public view returns (uint256) {
        return IERC20(GNS).balanceOf(address(this));
    }

    function balanceOfStakedGns() public view returns (uint256) {
        IGNSVault.User memory user = IGNSVault(GNS_VAULT).users(address(this));
        return user.stakedTokens;
    }

    function balanceOfRewards() public view returns (uint256) {
        return IGNSVault(GNS_VAULT).pendingRewardDai();
    }

    function _withdrawSome(uint256 _amountNeeded) internal {
        if (_amountNeeded == 0) return;

        if (daiToWant(balanceOfRewards()) >= _amountNeeded) {
            _sellRewards();
        }

        uint256 gnsToUnstake = Math.min(
            balanceOfStakedGns(),
            wantToGns(_amountNeeded - balanceOfWant())
        );

        if (gnsToUnstake > 0) {
            _exitPosition(gnsToUnstake);
        }
    }

    function _sellRewards() internal {
        IGNSVault(GNS_VAULT).harvest();
        uint256 balDai = IERC20(DAI).balanceOf(address(this));
        if (balDai > 0) {
            uint256 minAmountOut = (daiToWant(balDai) * slippage) / 10000;
            IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter
                .ExactInputSingleParams({
                    tokenIn: DAI,
                    tokenOut: address(want),
                    fee: DAI_USDC_UNI_FEE,
                    recipient: address(this),
                    amountIn: balDai,
                    amountOutMinimum: minAmountOut,
                    sqrtPriceLimitX96: 0
                });
            IV3SwapRouter(UNISWAP_V3_ROUTER).exactInputSingle(params);
        }
    }

    function _exitPosition(uint256 gnsAmount) internal {
        IGNSVault(GNS_VAULT).unstakeTokens(gnsAmount);

        uint256 minAmountOut = (gnsToWant(gnsAmount) * slippage) / 10000;
        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter
            .ExactInputParams({
                path: abi.encodePacked(
                    GNS,
                    GNS_ETH_UNI_FEE,
                    WETH,
                    ETH_USDC_UNI_FEE,
                    address(want)
                ),
                recipient: address(this),
                amountIn: gnsAmount,
                amountOutMinimum: minAmountOut
            });
        IV3SwapRouter(UNISWAP_V3_ROUTER).exactInput(params);
    }

    function ethToWant(
        uint256 ethAmount
    ) public view override returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            ETH_USDC_UNI_V3_POOL,
            TWAP_RANGE_SECS
        );
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                uint128(ethAmount),
                WETH,
                address(want)
            );
    }

    function wantToEth(uint256 wantAmount) public view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            ETH_USDC_UNI_V3_POOL,
            TWAP_RANGE_SECS
        );
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                uint128(wantAmount),
                address(want),
                WETH
            );
    }

    function gnsToWant(uint256 gnsAmount) public view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            GNS_ETH_UNI_V3_POOL,
            TWAP_RANGE_SECS
        );
        return
            ethToWant(
                OracleLibrary.getQuoteAtTick(
                    meanTick,
                    uint128(gnsAmount),
                    GNS,
                    WETH
                )
            );
    }

    function wantToGns(uint256 wantAmount) public view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            GNS_ETH_UNI_V3_POOL,
            TWAP_RANGE_SECS
        );
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                uint128(wantToEth(wantAmount)),
                WETH,
                GNS
            );
    }

    function daiToWant(uint256 daiAmount) public view returns (uint256) {
        (int24 meanTick, ) = OracleLibrary.consult(
            DAI_USDC_UNI_V3_POOL,
            DAI_USDC_TWAP_RANGE_SECS
        );
        return
            OracleLibrary.getQuoteAtTick(
                meanTick,
                uint128(daiAmount),
                DAI,
                address(want)
            );
    }

    function estimatedTotalAssets()
        public
        view
        virtual
        override
        returns (uint256 _wants)
    {
        _wants = balanceOfWant();
        _wants += gnsToWant(balanceOfGns());
        _wants += gnsToWant(balanceOfStakedGns());
        _wants += daiToWant(balanceOfRewards());
        _wants += daiToWant(balanceOfDai());
    }

    function prepareReturn(
        uint256 _debtOutstanding
    )
        internal
        override
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {
        uint256 _totalAssets = estimatedTotalAssets();
        uint256 _totalDebt = vault.strategies(address(this)).totalDebt;

        if (_totalAssets >= _totalDebt) {
            _profit = _totalAssets - _totalDebt;
            _loss = 0;
        } else {
            _profit = 0;
            _loss = _totalDebt - _totalAssets;
        }
        _withdrawSome(_debtOutstanding + _profit);

        uint256 _liquidWant = want.balanceOf(address(this));

        if (_liquidWant <= _profit) {
            // enough to pay profit (partial or full) only
            _profit = _liquidWant;
            _debtPayment = 0;
        } else {
            // enough to pay for all profit and _debtOutstanding (partial or full)
            _debtPayment = Math.min(_liquidWant - _profit, _debtOutstanding);
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        _sellRewards();

        uint256 _wantBal = balanceOfWant();
        if (_wantBal > _debtOutstanding) {
            uint256 _excessWant = _wantBal - _debtOutstanding;
            uint256 minAmountOut = (wantToGns(_excessWant) * slippage) / 10000;
            IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter
                .ExactInputParams({
                    path: abi.encodePacked(
                        address(want),
                        ETH_USDC_UNI_FEE,
                        WETH,
                        GNS_ETH_UNI_FEE,
                        GNS
                    ),
                    recipient: address(this),
                    amountIn: _excessWant,
                    amountOutMinimum: minAmountOut
                });
            IV3SwapRouter(UNISWAP_V3_ROUTER).exactInput(params);
        }

        uint256 gnsBal = balanceOfGns();
        if (gnsBal > 0) {
            IGNSVault(GNS_VAULT).stakeTokens(gnsBal);
        }
    }

    function liquidateAllPositions() internal override returns (uint256) {
        _sellRewards();
        _exitPosition(balanceOfStakedGns());
        return want.balanceOf(address(this));
    }

    function liquidatePosition(
        uint256 _amountNeeded
    ) internal override returns (uint256 _liquidatedAmount, uint256 _loss) {
        uint256 _wantBal = want.balanceOf(address(this));
        if (_wantBal >= _amountNeeded) {
            return (_amountNeeded, 0);
        }

        _withdrawSome(_amountNeeded - _wantBal);
        _wantBal = want.balanceOf(address(this));

        if (_amountNeeded > _wantBal) {
            _liquidatedAmount = _wantBal;
            _loss = _amountNeeded - _wantBal;
        } else {
            _liquidatedAmount = _amountNeeded;
        }
    }

    function prepareMigration(address _newStrategy) internal override {
        IGNSVault(GNS_VAULT).unstakeTokens(balanceOfStakedGns());
        IGNSVault(GNS_VAULT).harvest();
        IERC20(GNS).safeTransfer(_newStrategy, balanceOfGns());
        IERC20(DAI).safeTransfer(_newStrategy, balanceOfDai());
        IERC20(WETH).safeTransfer(_newStrategy, balanceOfWeth());
    }

    function protectedTokens()
        internal
        pure
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](3);
        protected[0] = GNS;
        protected[1] = DAI;
        protected[2] = WETH;
        return protected;
    }
}

