//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {IPolis} from "./IPolis.sol";
import {IAccessControlHolder, IAccessControl} from "./IAccessControlHolder.sol";
import {IPolisMinter} from "./IPolisMinter.sol";

import {SafeERC20} from "./SafeERC20.sol";
import {IERC20} from "./IERC20.sol";

contract PolisMinter is IAccessControlHolder, IPolisMinter {
    using SafeERC20 for IERC20;

    bytes32 internal constant POLIS_MINTER_WITH_PAYMENT_ADMIN =
        keccak256("POLIS_MINTER_WITH_PAYMENT_ADMIN");

    IPolis public immutable polis;
    IAccessControl public immutable override acl;
    IERC20 public override paymentToken;
    uint256 public override paymentValue;
    address public paymentReceiver;

    modifier onlyPolisMinterWithPaymentAdminRole() {
        if (!acl.hasRole(POLIS_MINTER_WITH_PAYMENT_ADMIN, msg.sender)) {
            revert OnlyPolisMinterRole();
        }
        _;
    }

    constructor(
        IAccessControl acl_,
        IPolis polis_,
        IERC20 payemntToken_,
        address paymentReceiver_,
        uint256 paymentValue_
    ) {
        acl = acl_;
        polis = polis_;
        paymentToken = payemntToken_;
        paymentReceiver = paymentReceiver_;
        paymentValue = paymentValue_;
    }

    function setPayment(
        IERC20 token,
        uint256 value,
        address wallet
    ) external override onlyPolisMinterWithPaymentAdminRole {
        paymentToken = token;
        paymentValue = value;
        paymentReceiver = wallet;
    }

    function mintWithPayment() external override {
        paymentToken.safeTransferFrom(
            msg.sender,
            paymentReceiver,
            paymentValue
        );
        polis.mintAsMinter(msg.sender);

        emit MintedWithPayment(msg.sender);
    }
}

