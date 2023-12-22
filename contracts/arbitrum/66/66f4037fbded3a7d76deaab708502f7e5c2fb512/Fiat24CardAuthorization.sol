// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./IFiat24Account.sol";

error Fiat24CardAuthorization__NotOperator(address sender);
error Fiat24CardAuthorization__NotAuthorizer(address sender);
error Fiat24CardAuthorization__Suspended();


contract Fiat24CardAuthorization is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant AUTHORIZER_ROLE = keccak256("AUTHORIZER_ROLE");

    uint public constant CARD_BOOKED = 9109;

    address public fiat24AccountAddress;
    address public eur24Address;

    event authorized(address indexed sender, uint256 amount);
    event booked(uint256 amount);

    function initialize(address fiat24AccountAddress_, address eur24Address_) public initializer {
        __AccessControl_init_unchained();
        __Pausable_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, msg.sender);
        fiat24AccountAddress = fiat24AccountAddress_;
        eur24Address = eur24Address_;
    }

    function authorize(address sender_, uint256 amount_) public {
        if(!(hasRole(AUTHORIZER_ROLE, _msgSender()))) revert Fiat24CardAuthorization__NotAuthorizer(_msgSender());
        if(paused()) revert Fiat24CardAuthorization__Suspended();
        IERC20Upgradeable(eur24Address).safeTransferFrom(sender_, address(this), amount_);
        emit authorized(sender_, amount_);
    }

    function book() public {
        if(!(hasRole(AUTHORIZER_ROLE, _msgSender()))) revert Fiat24CardAuthorization__NotAuthorizer(_msgSender());
        if(paused()) revert Fiat24CardAuthorization__Suspended();
        uint256 balance = IERC20Upgradeable(eur24Address).balanceOf(address(this));
        IERC20Upgradeable(eur24Address).safeTransfer(IFiat24Account(fiat24AccountAddress).ownerOf(CARD_BOOKED), balance);
        emit booked(balance);
    }

    function pause() external {
        if(!(hasRole(OPERATOR_ROLE, _msgSender()))) revert Fiat24CardAuthorization__NotOperator(_msgSender());
        _pause();
    }

    function unpause() external {
        if(!(hasRole(OPERATOR_ROLE, _msgSender()))) revert Fiat24CardAuthorization__NotOperator(_msgSender());
        _unpause();
    }
}
