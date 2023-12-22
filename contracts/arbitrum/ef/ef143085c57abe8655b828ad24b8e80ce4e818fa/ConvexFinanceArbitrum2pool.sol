pragma solidity ^0.8.9;

import {IERC20} from "./ERC20_IERC20.sol";
import {DefiiWithCustomEnter} from "./DefiiWithCustomEnter.sol";

contract ConvexFinanceArbitrum2pool is DefiiWithCustomEnter {
    IERC20 constant USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20 constant USDT = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    IERC20 constant CRV = IERC20(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);

    IPool constant CRVpool = IPool(0x7f90122BF0700F9E7e1F688fe926940E8839F353);
    IBooster constant booster =
        IBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    IRewardPool constant cvx2CRVPool =
        IRewardPool(0x971E732B5c91A59AEa8aa5B0c763E6d648362CF8);

    uint256 constant pid = 7;

    function enterParams(
        uint256 slippage
    ) external view returns (bytes memory) {
        require(slippage > 800, "Slippage must be >800, (>80%)");
        require(slippage < 1200, "Slippage must be <1200, (<120%)");
        uint256 usdcAmount = USDC.balanceOf(address(this));
        uint256 minAmountOut = CRVpool.calc_token_amount([usdcAmount, 0], true);
        return abi.encode(usdcAmount, (minAmountOut * slippage) / 1000);
    }

    function _enterWithParams(bytes memory params) internal override {
        (uint256 usdcAmount, uint256 minAmountOut) = abi.decode(
            params,
            (uint256, uint256)
        );
        USDC.approve(address(CRVpool), usdcAmount);
        uint256 crvAmount = CRVpool.add_liquidity(
            [usdcAmount, 0],
            minAmountOut
        );
        CRVpool.approve(address(booster), crvAmount);
        booster.depositAll(pid);
    }

    function _harvest() internal override {
        cvx2CRVPool.getReward(address(this));
        _claimIncentive(CRV);
    }

    function _exit() internal override {
        _harvest();
        uint256 cvx2Amount = cvx2CRVPool.balanceOf(address(this));
        cvx2CRVPool.withdraw(cvx2Amount, false);
        uint256 CRVAmount = CRVpool.balanceOf(address(this));
        CRVpool.remove_liquidity(CRVAmount, [uint256(0), uint256(0)]);
    }

    function hasAllocation() public view override returns (bool) {
        return cvx2CRVPool.balanceOf(address(this)) > 0;
    }

    function _withdrawFunds() internal override {
        withdrawERC20(USDC);
        withdrawERC20(USDT);
    }
}

interface IPool is IERC20 {
    function add_liquidity(
        uint256[2] memory _amounts,
        uint256 _min_mint_amount
    ) external returns (uint256);

    function calc_token_amount(
        uint256[2] memory amounts,
        bool is_deposit
    ) external view returns (uint256);

    function remove_liquidity(
        uint256 _burn_amount,
        uint256[2] memory _min_amounts
    ) external returns (uint256[2] memory);
}

interface IBooster {
    function depositAll(uint256 _pid) external returns (bool);

    function balanceOf(address arrg0) external view returns (uint256);

    function withdraw(uint256 _amount, bool _claim) external returns (bool);
}

interface IRewardPool is IERC20 {
    function getReward(address _account) external;

    function withdraw(uint256 _amount, bool _claim) external returns (bool);
}

