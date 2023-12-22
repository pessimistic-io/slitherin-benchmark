// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.10;

import "./VariableDebtToken.sol";
import {FlashLoanSimpleReceiverBase} from "./FlashLoanSimpleReceiverBase.sol";
import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";
import {IERC20} from "./IERC20.sol";
import {IStableSwap} from "./IStableSwap.sol";
import {IPool} from "./IPool.sol";
import "./console.sol";

contract FlashLoan is FlashLoanSimpleReceiverBase {
    address payable owner;
    IPool public mahalendPool;

    constructor(
        address _addressProvider,
        address _mahalendAddress
    ) FlashLoanSimpleReceiverBase(IPoolAddressesProvider(_addressProvider)) {
        owner = payable(msg.sender);
        mahalendPool = IPool(_mahalendAddress);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        console.log(
            "before usdc balance",
            IERC20(asset).balanceOf(address(this))
        );

        // we have the borrowed funds
        // approve pool
        IERC20(asset).approve(address(mahalendPool), amount);

        // call pool usdt supply function
        mahalendPool.supply(asset, amount, owner, 0);

        // call usdc borrow function
        // call credit deligation
        uint256 borrowAmount = (amount * 50) / 100;
        console.log(asset, borrowAmount, owner);

        mahalendPool.borrow(asset, borrowAmount, 2, 0, owner);
        console.log(38);

        uint256 amountOwed = amount + premium;

        console.log("amountOwed", amountOwed);
        console.log(
            "before usdc balance",
            IERC20(asset).balanceOf(address(this))
        );
        IERC20(asset).approve(address(POOL), amountOwed);
        return true;
    }

    function requestFlashLoan(address _supplyToken, uint256 _amount) public {
        address asset = _supplyToken;
        uint256 amount = _amount * 2;
        bytes memory params = "";

        IERC20(asset).transferFrom(msg.sender, address(this), _amount);

        POOL.flashLoanSimple(address(this), asset, amount, params, 0);

        console.log(62);
        console.log(
            "after usdt balance",
            IERC20(asset).balanceOf(address(this))
        );
    }

    function getBalance(address _tokenAddress) external view returns (uint256) {
        return IERC20(_tokenAddress).balanceOf(address(this));
    }
}

