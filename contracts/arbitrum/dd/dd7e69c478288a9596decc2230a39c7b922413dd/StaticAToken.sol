// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";

import "./IAToken.sol";
import "./ILendingPool.sol";
import "./Math.sol";
import {Checker} from "./Checker.sol";
import {TokenUtils} from "./TokenUtils.sol";

/// @title  StaticAToken
/// @author Savvy Defi
contract StaticAToken is ERC20 {
    using SafeERC20 for IERC20;

    address public lendingPool;
    address public aToken;
    address public immutable baseToken;

    uint8 private _decimals;

    constructor(
        address _aToken,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        Checker.checkArgument(_aToken != address(0), "zero aave token address");

        lendingPool = IAToken(_aToken).POOL();
        aToken = _aToken;
        baseToken = IAToken(_aToken).UNDERLYING_ASSET_ADDRESS();
        _decimals = TokenUtils.expectDecimals(aToken);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Deposits `ASSET` in the Aave protocol and mints static aTokens to msg.sender
     * @param recipient The address that will receive the static aTokens
     * @param amount The amount of underlying `ASSET` to deposit (e.g. deposit of 100 USDC)
     * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
     *   0 if the action is executed directly by the user, without any middle-man
     * @param fromUnderlying bool
     * - `true` if the msg.sender comes with underlying tokens (e.g. USDC)
     * - `false` if the msg.sender comes already with aTokens (e.g. aUSDC)
     * @return uint256 The amount of StaticAToken minted, static balance
     **/
    function deposit(
        address recipient,
        uint256 amount,
        uint16 referralCode,
        bool fromUnderlying
    ) external returns (uint256) {
        return
            _deposit(
                msg.sender,
                recipient,
                amount,
                referralCode,
                fromUnderlying
            );
    }

    /**
     * @dev Burns `amount` of static aToken, with recipient receiving the corresponding amount of `ASSET`
     * @param recipient The address that will receive the amount of `ASSET` withdrawn from the Aave protocol
     * @param amount The amount to withdraw, in static balance of StaticAToken
     * @param toUnderlying bool
     * - `true` for the recipient to get underlying tokens (e.g. USDC)
     * - `false` for the recipient to get aTokens (e.g. aUSDC)
     * @return amountToBurn: StaticATokens burnt, static balance
     * @return amountToWithdraw: underlying/aToken send to `recipient`, dynamic balance
     **/
    function withdraw(
        address recipient,
        uint256 amount,
        bool toUnderlying
    ) external returns (uint256, uint256) {
        return _withdraw(msg.sender, recipient, amount, 0, toUnderlying);
    }

    /**
     * @dev Converts an aToken or underlying amount to the what it is denominated on the aToken as
     * scaled balance, function of the principal and the liquidity index
     * @param amount The amount to convert from
     * @return uint256 The static (scaled) amount
     **/
    function dynamicToStaticAmount(
        uint256 amount
    ) public view returns (uint256) {
        return Math.rayDiv(amount, rate());
    }

    /**
     * @dev Utility method to get the current aToken balance of an user, from his staticAToken balance
     * @param account The address of the user
     * @return uint256 The aToken balance
     **/
    function dynamicBalanceOf(address account) external view returns (uint256) {
        return staticToDynamicAmount(balanceOf(account));
    }

    /**
     * @dev Converts a static amount (scaled balance on aToken) to the aToken/underlying value,
     * using the current liquidity index on Aave
     * @param amount The amount to convert from
     * @return uint256 The dynamic amount
     **/
    function staticToDynamicAmount(
        uint256 amount
    ) public view returns (uint256) {
        return Math.rayMul(amount, rate());
    }

    /**
     * @dev Returns the Aave liquidity index of the underlying aToken, denominated rate here
     * as it can be considered as an ever-increasing exchange rate
     * @return bytes32 The domain separator
     **/
    function rate() public view returns (uint256) {
        return ILendingPool(lendingPool).getReserveNormalizedIncome(baseToken);
    }

    function _deposit(
        address depositor,
        address recipient,
        uint256 amount,
        uint16 referralCode,
        bool fromUnderlying
    ) internal returns (uint256) {
        require(recipient != address(0), "INVALID_RECIPIENT");

        if (fromUnderlying) {
            IERC20(baseToken).safeTransferFrom(
                depositor,
                address(this),
                amount
            );

            IERC20(baseToken).safeApprove(lendingPool, amount);

            ILendingPool(lendingPool).deposit(
                baseToken,
                amount,
                address(this),
                referralCode
            );
        } else {
            IERC20(aToken).safeTransferFrom(depositor, address(this), amount);
        }

        uint256 amountToMint = dynamicToStaticAmount(amount);
        _mint(recipient, amountToMint);
        return amountToMint;
    }

    function _withdraw(
        address owner,
        address recipient,
        uint256 staticAmount,
        uint256 dynamicAmount,
        bool toUnderlying
    ) internal returns (uint256, uint256) {
        Checker.checkArgument(recipient != address(0), "INVALID_RECIPIENT");
        Checker.checkArgument(
            staticAmount == 0 || dynamicAmount == 0,
            "ONLY_ONE_AMOUNT_FORMAT_ALLOWED"
        );

        uint256 userBalance = balanceOf(owner);

        uint256 amountToWithdraw;
        uint256 amountToBurn;

        uint256 currentRate = rate();
        if (staticAmount > 0) {
            amountToBurn = (staticAmount > userBalance)
                ? userBalance
                : staticAmount;
            amountToWithdraw = (staticAmount > userBalance)
                ? _staticToDynamicAmount(userBalance, currentRate)
                : _staticToDynamicAmount(staticAmount, currentRate);
        } else {
            uint256 dynamicUserBalance = _staticToDynamicAmount(
                userBalance,
                currentRate
            );
            amountToWithdraw = (dynamicAmount > dynamicUserBalance)
                ? dynamicUserBalance
                : dynamicAmount;
            amountToBurn = _dynamicToStaticAmount(
                amountToWithdraw,
                currentRate
            );
        }

        _burn(owner, amountToBurn);

        if (toUnderlying) {
            ILendingPool(lendingPool).withdraw(
                baseToken,
                amountToWithdraw,
                recipient
            );
        } else {
            IERC20(aToken).safeTransfer(recipient, amountToWithdraw);
        }

        return (amountToBurn, amountToWithdraw);
    }

    function _dynamicToStaticAmount(
        uint256 _amount,
        uint256 _rate
    ) internal pure returns (uint256) {
        return Math.rayDiv(_amount, _rate);
    }

    function _staticToDynamicAmount(
        uint256 _amount,
        uint256 _rate
    ) internal pure returns (uint256) {
        return Math.rayMul(_amount, _rate);
    }
}

