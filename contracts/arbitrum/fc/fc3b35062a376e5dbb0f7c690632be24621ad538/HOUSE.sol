pragma solidity ^0.8.0;

import {SafeTransferLib, ERC20} from "./SafeTransferLib.sol";
import {Kernel, Module, Keycode} from "./Kernel.sol";

contract HOUSE is Module {
    using SafeTransferLib for ERC20;

    event Deposit(address indexed who, address indexed token, uint256 amount);
    event Withdrawal(address indexed who, address indexed token, uint256 amount);

    constructor(Kernel _kernel) Module(_kernel) {}

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return Keycode.wrap("HOUSE");
    }

    /********************************************/
    /************** USER-FACTING ****************/
    /********************************************/

    /// @notice Deposits `amount` of `token` on behalf of `from`
    /// @dev tracks `balanceBefore` and `balanceAfter` in the event a whitelisted token has fee on transfer enabled
    function depositERC20(
        ERC20 token,
        address from,
        uint256 amount
    ) external permissioned {
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(from, address(this), amount);
        uint256 balanceAfter = token.balanceOf(address(this));

        emit Deposit(from, address(token), balanceAfter - balanceBefore);
    }

    /// @notice Deposits `msg.value` on behalf of `from`
    function depositNative(address from) external payable permissioned {
        emit Deposit(from, address(0), msg.value);
    }

    /// @notice Withdraws `amount` of ERC20 `token` on behalf of `to`
    function withdrawERC20(
        ERC20 token,
        address to,
        uint256 amount
    ) external permissioned {
        token.safeTransfer(to, amount);
        emit Withdrawal(to, address(token), amount);
    }

    /// @notice Withdraws `amount` of native token on behalf of `to`
    /// @dev Only EOAs are reccomended to interact as a user with the house, hence using transfer
    function withdrawNative(
        address payable to,
        uint256 amount
    ) external permissioned {
        to.transfer(amount);
        emit Withdrawal(to, address(0), amount);
    }

    /********************************************/
    /************** OWNER LOGIC *****************/
    /********************************************/

    /// @notice Same as ownerWithdrawERC20(), but does not update internal balance accounting. *unsafe*
    function ownerEmergencyWithdrawERC20(
        ERC20 token,
        address to,
        uint256 amount
    ) external permissioned {
        token.safeTransfer(to, amount);
    }

    /// @notice Same as ownerWithdrawNative(), but does not update internal balance accounting. *unsafe*
    function ownerEmergencyWithdrawalNative(
        address payable to,
        uint256 amount
    ) external permissioned {
        SafeTransferLib.safeTransferETH(to, amount);
    }
}

