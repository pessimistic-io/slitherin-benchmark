// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IFiat24Account.sol";

error Fiat24CardApplication__NotTokenOwner();
error Fiat24CardApplication__NotOperator();
error Fiat24CardApplication__TokenDoesNotExist();
error Fiat24CardApplication__TokenNotLive();
error Fiat24CardApplication__BlockedForUpdate();
error Fiat24CardApplication__CardApplicationSuspended();

contract Fiat24CardApplication is Initializable, AccessControlUpgradeable, PausableUpgradeable {

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    struct CardApplication {
        bool available;
        string cardProvider;
        string cardApplicationData;
        uint256 blockedUntil;
    }

    uint256 public constant STATUS_LIVE = 5;

    uint256 public feeAccount;
    uint256 public blockingPeriod;

    // mapping tokenId => cardApplication (encrypted)
    mapping(uint256 => CardApplication) public cardApplication;
    // mapping currency symol => ERC20, e.g. "EUR24" => Fiat24EUR()
    mapping(string => IERC20) public currencies;

    IFiat24Account public fiat24Account;

    event CardApplicationAdded(uint256 indexed tokenId, address indexed sender, string indexed cardProvider, string cardApplication);

    function initialize(address fiat24AccountAddress_, uint256 blockingPeriod_, uint256 feeAccount_) public initializer {
        __AccessControl_init_unchained();
        __Pausable_init_unchained();
        _setupRole(OPERATOR_ROLE, msg.sender);
        fiat24Account = IFiat24Account(fiat24AccountAddress_);
        blockingPeriod = blockingPeriod_;
        feeAccount = feeAccount_;
    }

    function addCardApplicationWallesterEUR(uint256 tokenId_, string memory cardApplicationData_) external {
        if(paused()) {
            revert Fiat24CardApplication__CardApplicationSuspended();
        }
        if(!(tokenExists(tokenId_) && 
             (fiat24Account.ownerOf(tokenId_) == msg.sender || fiat24Account.historicOwnership(msg.sender) == tokenId_))) {
            revert Fiat24CardApplication__NotTokenOwner();
        }
        if(fiat24Account.status(tokenId_) != STATUS_LIVE) {
            revert Fiat24CardApplication__TokenNotLive();
        }
        CardApplication storage cardApplication_ = cardApplication[tokenId_];
        if(cardApplication_.available && block.timestamp < cardApplication_.blockedUntil) {
            revert Fiat24CardApplication__BlockedForUpdate();
        }
        cardApplication_.available = true;
        cardApplication_.cardProvider = "Wallester";
        cardApplication_.cardApplicationData = cardApplicationData_;
        cardApplication_.blockedUntil = block.timestamp + blockingPeriod;

        currencies["EUR24"].transferFrom(msg.sender, fiat24Account.ownerOf(feeAccount), 1000);
        emit CardApplicationAdded(tokenId_, msg.sender, "Wallester", cardApplicationData_);
    }

    function addCurrency( string memory currencySymbol_, address currencyAddress_) external {
        if(!(hasRole(OPERATOR_ROLE, msg.sender))) {
            revert Fiat24CardApplication__NotOperator();
        }
        currencies[currencySymbol_] = IERC20(currencyAddress_);
    }
    
    function setBlockingPeriod(uint256 blockingPeriod_) external {
        if(!(hasRole(OPERATOR_ROLE, msg.sender))) {
            revert Fiat24CardApplication__NotOperator();
        }
        blockingPeriod = blockingPeriod_;
    }

    function changeFeeAccount(uint256 feeAccount_) external {
        if(!(hasRole(OPERATOR_ROLE, msg.sender))) {
            revert Fiat24CardApplication__NotOperator();
        }
        if(tokenExists(feeAccount_)) {
            feeAccount = feeAccount_;
        } else {
            revert Fiat24CardApplication__TokenDoesNotExist();
        }
    }

    function tokenExists(uint256 tokenId_) public view returns(bool) {
        try fiat24Account.ownerOf(tokenId_) returns(address) {
            return true;
        } catch Error(string memory) {
            return false;
        } catch (bytes memory) {
            return false;
        }
    }

    function pause() external {
        if(!(hasRole(OPERATOR_ROLE, msg.sender))) {
            revert Fiat24CardApplication__NotOperator();
        }
        _pause();
    }

    function unpause() external {
        if(!(hasRole(OPERATOR_ROLE, msg.sender))) {
            revert Fiat24CardApplication__NotOperator();
        }
        _unpause();
    }

    function addDefaultAdminRole() external {
         if(!(hasRole(OPERATOR_ROLE, msg.sender))) {
            revert Fiat24CardApplication__NotOperator();
        }
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());       
    }
}
