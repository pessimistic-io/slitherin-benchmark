// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IPool} from "./IPool.sol";
import {IFlashLoanSimpleReceiver} from "./IFlashLoanSimpleReceiver.sol";

import {IERC20} from "./interfaces_IERC20.sol";
import {DefiiWithParams} from "./DefiiWithParams.sol";

contract RadiantArbitrumUsdc is DefiiWithParams {
    IERC20 constant USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20 constant rUSDC = IERC20(0x805ba50001779CeD4f59CfF63aea527D12B94829);
    IERC20 constant variableDebtUSDC =
        IERC20(0xf92d501e74bd1e4308E6676C38Ab4d84389d7Bf3);
    IERC20 constant RDNT = IERC20(0x0C4681e6C0235179ec3D4F4fc4DF3d14FDD96017);

    IRadiantPool constant radiantPool =
        IRadiantPool(0x2032b9A8e9F7e76768CA9271003d3e43E1616B1F);
    IRadiantChefIncentivesController constant incentivesController =
        IRadiantChefIncentivesController(
            0x287Ff908B4DB0b29B65B8442B0a5840455f0Db32
        );
    IMultiFeeDistribution constant multiFeeDistribution =
        IMultiFeeDistribution(0xc2054A8C33bfce28De8aF4aF548C48915c455c13);

    IPool constant aavePool = IPool(0x794a61358D6845594F94dc1DB02A252b5b4814aD);
    IRouter constant sushiSwapRouter =
        IRouter(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

    uint256 constant VARIABLE_INTEREST_RATE_MODE = 2;

    function encodeParams(uint8 loopCount, uint8 ltv)
        external
        pure
        returns (bytes memory encodedParams)
    {
        require(ltv < 100, "LTV must be in range [0, 100]");
        encodedParams = abi.encode(loopCount, ltv);
    }

    function hasAllocation() external view override returns (bool) {
        return variableDebtUSDC.balanceOf(address(this)) > 0;
    }

    function harvestParams() external view returns (bytes memory params) {
        address[] memory path = new address[](2);
        path[0] = address(RDNT);
        path[1] = address(USDC);

        // Price for 1.0 RDNT
        uint256[] memory prices = sushiSwapRouter.getAmountsOut(1e18, path);
        params = abi.encode((prices[1] * 99) / 100);
    }

    function _enterWithParams(bytes memory params) internal override {
        (uint8 loopCount, uint8 ltv) = abi.decode(params, (uint8, uint8));

        USDC.approve(address(radiantPool), type(uint256).max);

        uint256 balance = USDC.balanceOf(address(this));
        for (uint8 i = 0; i < loopCount; i++) {
            radiantPool.deposit(address(USDC), balance, address(this), 0);
            radiantPool.borrow(
                address(USDC),
                (balance * ltv) / 100,
                VARIABLE_INTEREST_RATE_MODE,
                0,
                address(this)
            );
            balance = USDC.balanceOf(address(this));
        }
        radiantPool.deposit(address(USDC), balance, address(this), 0);
        USDC.approve(address(radiantPool), 0);
    }

    function _exit() internal override {
        aavePool.flashLoanSimple(
            address(this),
            address(USDC),
            variableDebtUSDC.balanceOf(address(this)),
            bytes(""),
            0
        );
        _claim();
        _sellReward(0);
    }

    function _harvestWithParams(bytes memory params) internal override {
        uint256 minPrice = abi.decode(params, (uint256));

        _claim();
        _sellReward(minPrice);
    }

    function _claim() internal {
        address[] memory assets = new address[](2);
        assets[0] = address(rUSDC);
        assets[1] = address(variableDebtUSDC);

        incentivesController.claim(address(this), assets);
        multiFeeDistribution.exit(true, address(this));
    }

    function _sellReward(uint256 minPrice) internal {
        uint256 rdntBalance = RDNT.balanceOf(address(this));
        uint256 amountOutMin = (rdntBalance * minPrice) / 1e18;

        if (minPrice > 0 && amountOutMin == 0) {
            return;
        }

        address[] memory path = new address[](2);
        path[0] = address(RDNT);
        path[1] = address(USDC);
        RDNT.approve(address(sushiSwapRouter), rdntBalance);
        sushiSwapRouter.swapExactTokensForTokens(
            rdntBalance,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );
    }

    function _withdrawFunds() internal override {
        withdrawERC20(USDC);
    }

    function _harvest() internal override {
        revert("Use harvestWithParams");
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(address(this) == initiator, "FLASHLOAN initiator");
        require(msg.sender == address(aavePool), "FLASHLOAN sender");
        require(asset == address(USDC), "FLASHLOAN asset");

        USDC.approve(address(radiantPool), amount);
        radiantPool.repay(
            asset,
            amount,
            VARIABLE_INTEREST_RATE_MODE,
            address(this)
        );
        radiantPool.withdraw(address(USDC), type(uint256).max, address(this));

        USDC.approve(address(aavePool), amount + premium);
        return true;
    }
}

interface IRadiantPool {
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;

    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function repay(
        address asset,
        uint256 amount,
        uint256 rateMode,
        address onBehalfOf
    ) external returns (uint256);

    function withdraw(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external returns (uint256);
}

interface IRadiantChefIncentivesController {
    function claim(address _user, address[] calldata _tokens) external;
}

interface IMultiFeeDistribution {
    function exit(bool claimRewards, address onBehalfOf) external;
}

interface IRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(uint256 amountIn, address[] memory path)
        external
        view
        returns (uint256[] memory amounts);
}

