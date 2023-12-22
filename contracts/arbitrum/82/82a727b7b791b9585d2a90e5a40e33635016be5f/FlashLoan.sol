// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.10;

import {FlashLoanSimpleReceiverBase} from "./FlashLoanSimpleReceiverBase.sol";
import {IPoolAddressesProvider} from "./IPoolAddressesProvider.sol";
import {IERC20} from "./IERC20.sol";
import {IStableSwap} from "./IStableSwap.sol";
import {IPool} from "./IPool.sol";

contract FlashLoan is FlashLoanSimpleReceiverBase {
    IPool public mahalend;

    constructor(
        address _addressProvider,
        address _mahalendAddress
    ) FlashLoanSimpleReceiverBase(IPoolAddressesProvider(_addressProvider)) {
        mahalend = IPool(_mahalendAddress);
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address,
        bytes calldata params
    ) external override returns (bool) {
        (address who, uint256 ltv) = abi.decode(params, (address, uint256));

        // we have the borrowed funds
        // approve pool
        IERC20(asset).approve(address(mahalend), amount);

        // supply the asset to mahalend
        mahalend.supply(asset, amount, who, 0);

        // calculate how much to borrow of that same asset
        uint256 borrowAmount = (amount * ltv) / 100;

        // borrow the amount
        mahalend.borrow(asset, borrowAmount, 2, 0, who);

        // repay the flashloan
        IERC20(asset).approve(address(POOL), amount + premium);
        return true;
    }

    function flasloanOpen(
        address _supplyToken,
        uint256 _amount,
        uint256 ltv,
        uint256 leverage
    ) public {
        IERC20(_supplyToken).transferFrom(msg.sender, address(this), ltv);

        // execute fhe flashloan
        uint256 amount = _amount * leverage;
        bytes memory params = abi.encode(msg.sender, _amount);
        POOL.flashLoanSimple(address(this), _supplyToken, amount, params, 0);

        // refund any dush
        uint256 bal = IERC20(_supplyToken).balanceOf(address(this));
        IERC20(_supplyToken).transfer(msg.sender, bal);
    }
}

