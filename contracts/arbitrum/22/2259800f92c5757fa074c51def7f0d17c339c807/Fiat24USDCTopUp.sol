// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./draft-ERC20Permit.sol";
import "./AccessControl.sol";
import "./Pausable.sol";
import "./SafeMath.sol";

import "./F24.sol";
import "./Fiat24USD.sol";

contract Fiat24USDCTopUp is AccessControl, Pausable {
    using SafeMath for uint256;
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public constant THIRTYDAYS = 2592000;
    
    ERC20Permit USDC;
    Fiat24USD USD24;

    struct Quota {
        uint256 quota;
        uint256 quotaBegin;
        bool isAvailable;
    }
    
    uint256 public fee;
    uint256 public maxQuota;
    uint256 public minTopUpAmount;
    
    mapping (uint256 => Quota) public quotas; 
    
    Fiat24Account fiat24account;
    F24 f24;
    
    address public usd24TreasuryAddress;
    address public cryptoDeskAddress;
    
    constructor(address fiat24accountProxyAddress_, 
                address f24Address_, 
                address usdcAddress_, 
                address usd24Address, 
                address usd24TreasuryAddress_,
                address cryptoDeskAddress_, 
                uint256 fee_, 
                uint256 maxQuota_, 
                uint256 minTopUpAmount_) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(OPERATOR_ROLE, msg.sender);
        fee = fee_;
        maxQuota = maxQuota_;
        minTopUpAmount = minTopUpAmount_;
        fiat24account = Fiat24Account(fiat24accountProxyAddress_);
        f24 = F24(f24Address_);
        USDC = ERC20Permit(usdcAddress_);
        USD24 = Fiat24USD(usd24Address);
        usd24TreasuryAddress = usd24TreasuryAddress_;
        cryptoDeskAddress = cryptoDeskAddress_;
    }
    
    function topUpUsdc(uint256 usdcAmount_) external {
        require(!paused(), "Fiat24USDCTopUp: Top-up currently suspended");
        uint256 tokenId = getTokenByAddress(msg.sender);
        require(tokenId != 0, "Fiat24USDCTopUp: no account for this address");
        require(tokenEligibleForUsdcTopUp(tokenId), "Fiat24USDCTopUp: account not eligible for crypto top-up");
        require(usdcAmount_ >= minTopUpAmount, "Fiat24USDCTopUp: top-up amount < min top-up amount");
        uint256 quota = getMaxQuota(tokenId);
        require(usdcAmount_ <= quota, "Fiat24USDCTopUp: Not sufficient month quota");
        uint256 topUpAmount = getTopUpAmount(tokenId, msg.sender, usdcAmount_);
        require(USDC.transferFrom(msg.sender, cryptoDeskAddress, usdcAmount_), "Fiat24USDCTopUp: USDC transfer failed");
        require(USD24.transferFrom(usd24TreasuryAddress, msg.sender, topUpAmount), "Fiat24USDCTopUp: USD24 token transfer failed");
        updateQuota(tokenId, usdcAmount_);
    }

    function topUpUsdcWithPermit(uint256 usdcAmount_, bytes memory sig, uint256 deadline) external {
        require(!paused(), "Fiat24USDCTopUp: Top-up currently suspended");
        uint256 tokenId = getTokenByAddress(msg.sender);
        require(tokenId != 0, "Fiat24USDCTopUp: no account for this address");
        require(tokenEligibleForUsdcTopUp(tokenId), "Fiat24USDCTopUp: account not eligible for crypto top-up");
        require(usdcAmount_ >= minTopUpAmount, "Fiat24USDCTopUp: top-up amount < min top-up amount");
        uint256 quota = getMaxQuota(tokenId);
        require(usdcAmount_ <= quota, "Fiat24USDCTopUp: Not sufficient month quota");
        uint256 topUpAmount = getTopUpAmount(tokenId, msg.sender, usdcAmount_);

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := and(mload(add(sig, 65)), 255)
        }
        if (v < 27) v += 27;
        USDC.permit(msg.sender, address(this), usdcAmount_, deadline, v, r ,s);

        require(USDC.transferFrom(msg.sender, cryptoDeskAddress, usdcAmount_), "Fiat24USDCTopUp: USDC transfer failed");
        require(USD24.transferFrom(usd24TreasuryAddress, msg.sender, topUpAmount), "Fiat24USDCTopUp: USD24 token transfer failed");
        updateQuota(tokenId, usdcAmount_);
    }
    
    function getMaxQuota(uint256 tokenId_) public view returns(uint256) {
        uint256 quota = 0;
        if(tokenEligibleForUsdcTopUp(tokenId_)) {
            if(quotas[tokenId_].isAvailable) {
                uint256 quotaEnd = quotas[tokenId_].quotaBegin + THIRTYDAYS;
                if(block.timestamp > quotaEnd) {
                    quota =  maxQuota;
                } else {
                    quota = maxQuota - quotas[tokenId_].quota;
                }
            } else {
                quota = maxQuota;
            }
        } 
        return quota;
    }

    function getUsedQuota(uint256 tokenId_) public view returns(uint256) {
        uint256 quota = 0;
        if(tokenEligibleForUsdcTopUp(tokenId_)) {
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
        } else {
            quota = maxQuota;
        }
        return quota;
    }
    
    function updateQuota(uint256 tokenId_, uint256 usdcAmount_) internal {
        if(quotas[tokenId_].isAvailable) {
            if((quotas[tokenId_].quotaBegin + THIRTYDAYS) < block.timestamp) {
                quotas[tokenId_].quota = usdcAmount_;
                quotas[tokenId_].quotaBegin = block.timestamp;
            } else {
                quotas[tokenId_].quota += usdcAmount_;
            }
        } else {
            quotas[tokenId_].quota = usdcAmount_;
            quotas[tokenId_].quotaBegin = block.timestamp;
            quotas[tokenId_].isAvailable = true;
        }
    }
    
    function getTopUpAmount(uint256 tokenId_, address owner_, uint256 usdcAmount_) public view returns(uint256) {
        uint256 topUpAmount;
        if(tokenEligibleForUsdcTopUp(tokenId_) && fiat24account.checkLimit(tokenId_, USD24.convertToChf(usdcAmount_))) {
            (,topUpAmount) = usdcAmount_.trySub(calculateFee(tokenId_, owner_, usdcAmount_));
        } else {
            topUpAmount = 0;
        }
        return topUpAmount;
    }
    
    function calculateFee(uint256 tokenId_, address owner_, uint256 usdcAmount_) public view returns(uint256) {
        uint256 f24Balance = f24.balanceOf(owner_);
        (,uint256 freeTier) = f24Balance.trySub(getUsedQuota(tokenId_));
        (,uint256 feeTier) = usdcAmount_.trySub(freeTier);
        return feeTier * fee / 10000;
    }

    function getTiers(uint256 tokenId_, address owner_, uint256 usdcAmount_) external view returns(uint256, uint256) {
        uint256 f24Balance = f24.balanceOf(owner_);
        (,uint256 freeQuota) = f24Balance.trySub(getUsedQuota(tokenId_));
        (,uint256 standardTier) = usdcAmount_.trySub(freeQuota);
        (,uint256 freeTier) = usdcAmount_.trySub(standardTier);
        return (standardTier, freeTier);
    }
    
    function changeFee(uint256 newFee_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24USDCTopUp: Not an operator");
        fee = newFee_;
    }

    function changeMaxQuota(uint256 maxQuota_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24USDCTopUp: Not an operator");
        maxQuota = maxQuota_;
    }

    function changeMinTopUpAmount(uint256 minTopUpAmount_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24USDCTopUp: Not an operator");
        minTopUpAmount = minTopUpAmount_;
    }

    function changeCryptoDeskAddress(address cryptoDeskAddress_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24USDCTopUp: Not an operator");
        cryptoDeskAddress = cryptoDeskAddress_;
    }

    function changeUsd24TreasuryAdddress(address usd24TreasuryAddress_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24USDCTopUp: Not an operator");
        usd24TreasuryAddress = usd24TreasuryAddress_;
    }
    
    function tokenEligibleForUsdcTopUp(uint256 tokenId_) public view returns(bool) {
        return tokenExists(tokenId_) && 
               (fiat24account.status(tokenId_) == Fiat24Account.Status.Live ||
                fiat24account.status(tokenId_) == Fiat24Account.Status.Tourist);
    }
    
    function tokenExists(uint256 tokenId_) internal view returns(bool){
        try fiat24account.ownerOf(tokenId_) returns(address) {
            return true;
        } catch Error(string memory) {
            return false;
        } catch (bytes memory) {
            return false;
        }
    }

    function getTokenByAddress(address owner) internal view returns(uint256) {
        try fiat24account.tokenOfOwnerByIndex(owner, 0) returns(uint256 tokenid) {
            return tokenid;
        } catch Error(string memory) {
            return 0;
        } catch (bytes memory) {
            return 0;
        }
    }

    function pause() public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Fiat24Account: Not an admin");
        _pause();
    }

    function unpause() public {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Fiat24Account: Not an admin");
        _unpause();
    }
}
