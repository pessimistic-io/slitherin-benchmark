//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IGatewayRegistry} from "./IGatewayRegistry.sol";
import {IERC20} from "./IERC20.sol";
import {Context} from "./Context.sol";
import {AccessControlEnumerable} from "./AccessControlEnumerable.sol";
import {AccessControl} from "./AccessControl.sol";

address constant FEE_CURRENCY = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

contract Lender is Context, AccessControlEnumerable {
    event Lent();
    event Repayed();

    bytes32 public constant LENDER_ADMIN = keccak256("LENDER_ADMIN");
    bytes32 public constant FUNDS_ADMIN = keccak256("FUNDS_ADMIN");

    mapping(bytes32 => uint256) public loans;

    constructor(address roleAdminAddress) payable {
        AccessControlEnumerable._grantRole(
            AccessControl.DEFAULT_ADMIN_ROLE,
            roleAdminAddress
        );
        AccessControlEnumerable._grantRole(FUNDS_ADMIN, roleAdminAddress);
    }

    function deposit(address erc20, uint256 amount) external payable {
        if (erc20 == FEE_CURRENCY) {
            require(msg.value == amount, "Lender: insufficient msg.value");
        } else {
            IERC20(erc20).transferFrom(_msgSender(), address(this), amount);
        }
    }

    function withdraw(address erc20, uint256 amount) external {
        require(hasRole(LENDER_ADMIN, _msgSender()), "Lender: not funds admin");
        if (erc20 == FEE_CURRENCY) {
            payable(_msgSender()).transfer(amount);
        } else {
            IERC20(erc20).transfer(_msgSender(), amount);
        }
    }

    function borrow(
        address token,
        bytes32 borrower,
        uint256 amount
    ) external returns (uint256) {
        require(
            hasRole(LENDER_ADMIN, _msgSender()),
            "Lender: not lender admin"
        );
        loans[borrower] += amount;
        if (token == FEE_CURRENCY) {
            payable(address(_msgSender())).transfer(amount);
        } else {
            IERC20(token).transfer(_msgSender(), amount);
        }
        return amount;
    }

    function repay(
        address erc20,
        bytes32 borrower,
        uint256 amount
    ) external payable returns (uint256) {
        require(
            hasRole(LENDER_ADMIN, _msgSender()),
            "Lender: not lender admin"
        );

        uint256 change = 0;
        if (amount > loans[borrower]) {
            change = amount - loans[borrower];
            loans[borrower] = 0;
        } else {
            loans[borrower] -= amount;
        }

        if (erc20 == FEE_CURRENCY) {
            require(amount == msg.value, "Lender: insufficient msg.value");
            if (change > 0) {
                payable(_msgSender()).transfer(change);
            }
        } else {
            IERC20(erc20).transferFrom(
                _msgSender(),
                address(this),
                amount - change
            );
        }
        return change;
    }
}

