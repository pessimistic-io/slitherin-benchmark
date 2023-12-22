// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./IFiat24Account.sol";
import "./DigitsOfUint.sol";

error Fiat24CardAuthorization__NotOperator(address sender);
error Fiat24CardAuthorization__NotAuthorizer(address sender);
error Fiat24CardAuthorization__Suspended();


contract Fiat24CardAuthorization is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using DigitsOfUint for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant AUTHORIZER_ROLE = keccak256("AUTHORIZER_ROLE");

    uint public constant CARD_BOOKED = 9109;
    uint public constant SUNDRY = 9103;
    uint public constant TREASURY = 9100;

    address public fiat24AccountAddress;
    address public eur24Address;
    address public f24Address;

    bool public f24AirdropIsActive;

    event authorized(string authorizationId, string cardId, uint256 indexed tokenId, address indexed sender, uint256 amount);
    event reversed(string authorizationId, string originalAuthorizationId, string cardId, uint256 indexed tokenId, address indexed sender, uint256 amount);

    function initialize(address fiat24AccountAddress_, address eur24Address_, address f24Address_) public initializer {
        __AccessControl_init_unchained();
        __Pausable_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, msg.sender);
        fiat24AccountAddress = fiat24AccountAddress_;
        eur24Address = eur24Address_;
        f24Address = f24Address_;
    }

    function authorize(string memory authorizationId_, string memory cardId_, uint256 tokenId_, address sender_, uint256 amount_) public {
        if(!(hasRole(AUTHORIZER_ROLE, _msgSender()))) revert Fiat24CardAuthorization__NotAuthorizer(_msgSender());
        if(paused()) revert Fiat24CardAuthorization__Suspended();
        IERC20Upgradeable(eur24Address).safeTransferFrom(sender_, IFiat24Account(fiat24AccountAddress).ownerOf(CARD_BOOKED), amount_);
        if(f24AirdropIsActive) {
            uint numOfDigits = tokenId_.numDigits();
            uint256 f24Amount = 0;
            if(amount_>= 100) {
                if(numOfDigits >= 5) {
                    f24Amount = amount_*1/100;
                } else if(numOfDigits == 4) {
                    f24Amount = amount_*2/100;
                } else if(numOfDigits == 3) {
                    f24Amount = amount_*3/100;
                } else if(numOfDigits == 2) {
                    f24Amount = amount_*4/100;
                } else if(numOfDigits == 1) {
                    f24Amount = amount_*5/100;
                }
                if(f24Amount > 0) {
                    IERC20Upgradeable(f24Address).safeTransferFrom(IFiat24Account(fiat24AccountAddress).ownerOf(TREASURY), sender_, f24Amount);
                }
            }
        }
        emit authorized(authorizationId_, cardId_, tokenId_, sender_, amount_);
    }

    function reverse(string memory authorizationId_,  string memory originalAuthorizationId_, string memory cardId_, uint256 tokenId_, address sender_, uint256 amount_) public {
        if(!(hasRole(AUTHORIZER_ROLE, _msgSender()))) revert Fiat24CardAuthorization__NotAuthorizer(_msgSender());
        if(paused()) revert Fiat24CardAuthorization__Suspended();
        IERC20Upgradeable(eur24Address).safeTransferFrom(IFiat24Account(fiat24AccountAddress).ownerOf(CARD_BOOKED), IFiat24Account(fiat24AccountAddress).ownerOf(SUNDRY), amount_);
        emit reversed(authorizationId_, originalAuthorizationId_, cardId_, tokenId_, sender_, amount_);
    }

    function setF24Address(address f24Address_) external {
        if(!(hasRole(OPERATOR_ROLE, _msgSender()))) revert Fiat24CardAuthorization__NotOperator(_msgSender());
        f24Address = f24Address_;
    }

    function setF24Airdrop(bool f24Airdrop_) external {
        if(!(hasRole(OPERATOR_ROLE, _msgSender()))) revert Fiat24CardAuthorization__NotOperator(_msgSender());
        f24AirdropIsActive = f24Airdrop_;
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
