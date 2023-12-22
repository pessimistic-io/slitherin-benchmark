// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IERC20.sol";
import "./SafeMath.sol";
import "./IFiat24Account.sol";
import "./IFiat24Token.sol";
import "./IF24TimeLock.sol";

error Fiat24CrossChainBooking__NotOperator();
error Fiat24CrossChainBooking__NotBooker();
error Fiat24CrossChainBooking__CrossChainBookingSuspended();
error Fiat24CrossChainBooking__CurrencyNotAvailable();
error Fiat24CrossChainBooking__TokenNotAvailable();
error Fiat24CrossChainBooking__TransferNotAllowed();
error Fiat24CrossChainBooking__TxAlreadyBooked();

contract Fiat24CrossChainBooking is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeMath for uint256;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant BOOKER_ROLE = keccak256("BOOKER_ROLE");

    uint256 public constant STATUS_LIVE = 5;
    uint256 public constant STATUS_TOURIST = 2;
    uint256 public constant CRYPTO_DESK = 9105;
    uint256 public constant SUNDRY = 9103;
    uint256 public constant PL = 9203;

    uint256 public constant THIRTYDAYS = 2592000;
    uint256 public constant FOURDECIMALS = 10000;

    struct Currency {
        string currencySymbol;
        bool available;
    }
    struct Quota {
        uint256 quota;
        uint256 quotaBegin;
        bool isAvailable;
    }

    mapping(uint256 => mapping(bytes32 => bool)) public xBookings;
    mapping(address => Currency) public currencies;
    mapping (uint256 => Quota) public quotas; 

    uint256 public fee;

    address public f24DeskAddress;

    IFiat24Account public fiat24Account;
    IF24TimeLock public f24TimeLock;
    IERC20 public f24;
    IFiat24Token public usd24;

    //F24 airdrop
    uint256 public f24AirdropStart;
    uint256 public f24PerUsd24;
    bool public f24AirdropPaused;

    event XBooking(uint256 networkId, bytes32 indexed tx,  uint256 indexed blockNumber, uint256 indexed tokenId, string currency, uint256 amount);

    function initialize(address fiat24AccountAddress_,
                        address f24TimeLockAddress_,
                        address f24Address_,
                        address usd24Address_,
                        address f24DeskAddress_,
                        uint256 fee_,
                        uint256 f24AirdropStart_,
                        uint256 f24PerUsd24_,
                        bool f24AirdropPaused_) public initializer {
        __AccessControl_init_unchained();
        __Pausable_init_unchained();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _msgSender());
        fiat24Account = IFiat24Account(fiat24AccountAddress_);
        f24TimeLock = IF24TimeLock(f24TimeLockAddress_);
        f24 = IERC20(f24Address_);
        usd24 = IFiat24Token(usd24Address_);
        f24DeskAddress = f24DeskAddress_;
        fee = fee_;
        f24AirdropStart = f24AirdropStart_;
        f24PerUsd24 = f24PerUsd24_;
        f24AirdropPaused = f24AirdropPaused_;
    }

    function xbook(uint256 networkId_, bytes32 tx_, uint256 blockNumber_, address recipient_, uint256 amount_, address currencyAddress_) external {
        if(paused()) {
            revert Fiat24CrossChainBooking__CrossChainBookingSuspended();
        }
        if(!hasRole(BOOKER_ROLE, msg.sender)){
            revert Fiat24CrossChainBooking__NotBooker();
        }

        if(xBookings[networkId_][tx_]) {
            revert Fiat24CrossChainBooking__TxAlreadyBooked();
        }

        IFiat24Token currency;
        if(currencies[currencyAddress_].available) {
            currency = IFiat24Token(currencyAddress_);
        } else {
            revert Fiat24CrossChainBooking__CurrencyNotAvailable();
        }

        uint256 fiat24TokenAmount = amount_.div(FOURDECIMALS);
        uint256 feeAmount;
        uint256 tokenId = getTokenByAddress(recipient_);
        if(tokenId == 0 || (fiat24Account.status(tokenId) != STATUS_LIVE && fiat24Account.status(tokenId) != STATUS_TOURIST)) {
            tokenId = SUNDRY;
            currency.transferFrom(fiat24Account.ownerOf(CRYPTO_DESK), fiat24Account.ownerOf(SUNDRY), fiat24TokenAmount);
        } else {
            uint256 usd24Amount;
            if(keccak256(abi.encodePacked(currencies[currencyAddress_].currencySymbol)) == keccak256(abi.encodePacked("USD24"))) {
                usd24Amount = fiat24TokenAmount;
            } else {
                usd24Amount = usd24.convertFromChf(currency.convertToChf(fiat24TokenAmount));
            }
            uint256 usd24FeeAmount = calculateFee(tokenId, usd24Amount);
            feeAmount = currency.convertFromChf(usd24.convertToChf(usd24FeeAmount));
            if(currency.tokenTransferAllowed(fiat24Account.ownerOf(CRYPTO_DESK), recipient_, fiat24TokenAmount-feeAmount)) {
                currency.transferFrom(fiat24Account.ownerOf(CRYPTO_DESK), recipient_, fiat24TokenAmount-feeAmount);
                currency.transferFrom(fiat24Account.ownerOf(CRYPTO_DESK), fiat24Account.ownerOf(PL), feeAmount);
                updateQuota(tokenId, usd24Amount-usd24FeeAmount);
                if(!f24AirdropPaused) {
                    f24Airdrop(usd24Amount, recipient_);
                }
            } else {
                currency.transferFrom(fiat24Account.ownerOf(CRYPTO_DESK), fiat24Account.ownerOf(SUNDRY), fiat24TokenAmount);
            }
        }
        
        xBookings[networkId_][tx_] = true;
        emit XBooking(networkId_, tx_, blockNumber_, tokenId, currencies[currencyAddress_].currencySymbol, fiat24TokenAmount-feeAmount);
    }

    function calculateFee(uint256 tokenId_, uint256 usd24Amount_) public view returns(uint256) {
        uint256 f24Balance = getF24LockedAmount(tokenId_);
        (,uint256 freeTier) = f24Balance.trySub(getUsedQuota(tokenId_));
        (,uint256 feeTier) = usd24Amount_.trySub(freeTier);
        return feeTier.mul(fee).div(100);
    }

    function getTiers(uint256 tokenId_, uint256 usd24Amount_) external view returns(uint256, uint256) {
        uint256 f24Balance = getF24LockedAmount(tokenId_);
        (,uint256 freeQuota) = f24Balance.trySub(getUsedQuota(tokenId_));
        (,uint256 standardTier) = usd24Amount_.trySub(freeQuota);
        (,uint256 freeTier) = usd24Amount_.trySub(standardTier);
        return (standardTier, freeTier);
    }

    function getF24LockedAmount(uint256 tokenId_) internal view returns(uint256){
        IF24TimeLock.LockedAmount memory lockedAmount = f24TimeLock.lockedAmounts(tokenId_);
        return lockedAmount.lockedAmount;
    }

    function getUsedQuota(uint256 tokenId_) public view returns(uint256) {
        uint256 quota = 0;
        if(quotas[tokenId_].isAvailable) {
            uint256 quotaEnd = quotas[tokenId_].quotaBegin + THIRTYDAYS;
            if(quotas[tokenId_].quotaBegin == 0 || block.timestamp > quotaEnd) {
                quota = 0;
            } else {
                quota = quotas[tokenId_].quota;
            }
        } else {
            quota = 0;
        }
        return quota;
    }
    
    function updateQuota(uint256 tokenId_, uint256 usd24Amount_) internal {
        if(quotas[tokenId_].isAvailable) {
            if((quotas[tokenId_].quotaBegin + THIRTYDAYS) < block.timestamp) {
                quotas[tokenId_].quota = usd24Amount_;
                quotas[tokenId_].quotaBegin = block.timestamp;
            } else {
                quotas[tokenId_].quota += usd24Amount_;
            }
        } else {
            quotas[tokenId_].quota = usd24Amount_;
            quotas[tokenId_].quotaBegin = block.timestamp;
            quotas[tokenId_].isAvailable = true;
        }
    }

    function f24Airdrop(uint256 usd24Amount_, address recipient_) internal {
        uint256 f24Balance = f24.balanceOf(f24DeskAddress);
        if(block.timestamp >= f24AirdropStart && f24Balance > 0) {
            uint256 f24Amount = usd24Amount_.div(f24PerUsd24);
            f24Amount = f24Amount < f24Balance ? f24Amount : f24Balance;
            f24.transferFrom(f24DeskAddress, recipient_, f24Amount);
        }
    }

    function pauseF24Airdrop() external {
        if(!hasRole(OPERATOR_ROLE, msg.sender)){
            revert Fiat24CrossChainBooking__NotOperator();
        }
        f24AirdropPaused = true;
    }

    function unpauseF24Airdrop() external {
        if(!hasRole(OPERATOR_ROLE, msg.sender)){
            revert Fiat24CrossChainBooking__NotOperator();
        }
        f24AirdropPaused = false;
    }

    function changeF24AirdropStart(uint256 f24AirdropStart_) external {
        if(!hasRole(OPERATOR_ROLE, msg.sender)){
            revert Fiat24CrossChainBooking__NotOperator();
        }
        f24AirdropStart = f24AirdropStart_;
    }

    function changeF24PerUsd24(uint256 f24PerUsd24_) external {
        if(!hasRole(OPERATOR_ROLE, msg.sender)){
            revert Fiat24CrossChainBooking__NotOperator();
        }
        f24PerUsd24 = f24PerUsd24_;
    }

    function changeF24DeskAdddress(address f24DeskAddress_) external {
        if(!hasRole(OPERATOR_ROLE, msg.sender)){
            revert Fiat24CrossChainBooking__NotOperator();
        }
        f24DeskAddress = f24DeskAddress_;
    }

    function getTokenByAddress(address owner) public view returns(uint256) {
        try fiat24Account.tokenOfOwnerByIndex(owner, 0) returns(uint256 tokenid) {
            return tokenid;
        } catch Error(string memory) {
            return fiat24Account.historicOwnership(owner);
        } catch (bytes memory) {
            return fiat24Account.historicOwnership(owner);
        }
    }

    function addCurrency(address currencyAddress_, string memory currencySymbol_) external {
        if(!hasRole(OPERATOR_ROLE, msg.sender)){
            revert Fiat24CrossChainBooking__NotOperator();
        }
        currencies[currencyAddress_].currencySymbol = currencySymbol_;
        currencies[currencyAddress_].available = true;  
    }

    function changeFee(uint256 newFee_) external {
        if(!hasRole(OPERATOR_ROLE, msg.sender)){
            revert Fiat24CrossChainBooking__NotOperator();
        }
        fee = newFee_;
    }

    function pause() public {
        if(!hasRole(OPERATOR_ROLE, msg.sender)){
            revert Fiat24CrossChainBooking__NotOperator();
        }
        _pause();
    }

    function unpause() public {
        if(!hasRole(OPERATOR_ROLE, msg.sender)){
            revert Fiat24CrossChainBooking__NotOperator();
        }
        _unpause();
    }
}
