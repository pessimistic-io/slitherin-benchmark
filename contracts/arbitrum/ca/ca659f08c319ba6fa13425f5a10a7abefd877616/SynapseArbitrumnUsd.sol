// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./ERC20_IERC20.sol";
import {Defii} from "./Defii.sol";
import {DefiiWithCustomExit} from "./DefiiWithCustomExit.sol";

contract SynapseArbitrumnUsd is Defii, DefiiWithCustomExit {
    IERC20 constant USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    IERC20 constant USDT = IERC20(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);

    IERC20 constant nUSDLP = IERC20(0xcFd72be67Ee69A0dd7cF0f846Fc0D98C33d60F16);
    IERC20 constant SYN = IERC20(0x080F6AEd32Fc474DD5717105Dba5ea57268F46eb);

    ISwapFlashLoan constant swapFlashLoan =
        ISwapFlashLoan(0x9Dd329F5411466d9e0C488fF72519CA9fEf0cb40);
    IMiniChefV2 constant miniChef =
        IMiniChefV2(0x73186f2Cf2493f20836b17b21ae79fc12934E207);
    uint256 constant pid = 3;

    function hasAllocation() public view override returns (bool) {
        return miniChef.userInfo(pid, address(this)).amount > 0;
    }

    function _enter() internal override {
        uint256 usdcBalance = USDC.balanceOf(address(this));
        USDC.approve(address(swapFlashLoan), usdcBalance);

        uint256[] memory amounts = new uint256[](3);
        amounts[1] = usdcBalance;
        uint256 nUSDLPAmount = swapFlashLoan.addLiquidity(
            amounts,
            0,
            block.timestamp
        );

        nUSDLP.approve(address(miniChef), nUSDLPAmount);
        miniChef.deposit(pid, nUSDLPAmount, address(this));
    }

    function exitParams(uint256 slippage) public view returns (bytes memory) {
        require(slippage >= 800, "Slippage must be >800, (>80%)");
        require(slippage <= 1200, "Slippage must be <1200, (<120%)");

        uint256 usdcPerLp = swapFlashLoan.calculateRemoveLiquidityOneToken(
            1e18,
            1
        );
        uint256 usdtPerLp = swapFlashLoan.calculateRemoveLiquidityOneToken(
            1e18,
            2
        );

        uint8 returnTokenIndex;
        uint256 tokenAmounts;

        if (usdcPerLp > usdtPerLp) {
            returnTokenIndex = 1;
            tokenAmounts = usdcPerLp;
        } else {
            returnTokenIndex = 2;
            tokenAmounts = usdtPerLp;
        }

        return abi.encode(returnTokenIndex, ((tokenAmounts * slippage) / 1000));
    }

    function _exitWithParams(bytes memory params) internal override {
        (uint8 tokenIndex, uint256 tokenPerLp) = abi.decode(
            params,
            (uint8, uint256)
        );
        IMiniChefV2.UserInfo memory balanceInfo = miniChef.userInfo(
            pid,
            address(this)
        );

        miniChef.withdrawAndHarvest(pid, balanceInfo.amount, address(this));
        uint256 amountToWithdraw = nUSDLP.balanceOf(address(this));
        nUSDLP.approve(address(swapFlashLoan), amountToWithdraw);
        swapFlashLoan.removeLiquidityOneToken(
            amountToWithdraw,
            tokenIndex,
            (amountToWithdraw * tokenPerLp) / 1e18,
            block.timestamp
        );

        _claimIncentive(SYN);
    }

    function _exit() internal override(Defii, DefiiWithCustomExit) {
        _exitWithParams(exitParams(995));
    }

    function _harvest() internal override {
        miniChef.harvest(pid, address(this));
        _claimIncentive(SYN);
    }

    function _withdrawFunds() internal override {
        _withdrawERC20(USDC);
        _withdrawERC20(USDT);
    }
}

interface ISwapFlashLoan {
    function addLiquidity(
        uint256[] calldata amounts,
        uint256 minToMint,
        uint256 deadline
    ) external returns (uint256);

    function removeLiquidityOneToken(
        uint256 tokenAmount,
        uint8 tokenIndex,
        uint256 minAmount,
        uint256 deadline
    ) external returns (uint256);

    function calculateRemoveLiquidityOneToken(
        uint256 tokenAmount,
        uint8 tokenIndex
    ) external view returns (uint256 availableTokenAmount);
}

interface IMiniChefV2 {
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    function deposit(
        uint256 pid,
        uint256 amount,
        address to
    ) external;

    function withdrawAndHarvest(
        uint256 pid,
        uint256 amount,
        address to
    ) external;

    function harvest(uint256 pid, address to) external;

    function userInfo(uint256 pid, address userAddress)
        external
        view
        returns (UserInfo memory);
}

