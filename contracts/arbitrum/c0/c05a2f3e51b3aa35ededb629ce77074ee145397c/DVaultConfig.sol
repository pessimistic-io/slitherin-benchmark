// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Ownable.sol";

interface Metadata {

    function decimals() external view returns (uint8);
}

contract DVaultConfig is Ownable {

    address _feeAddress = 0x89A674E8ef54554a0519885295d4FC5d972De140;
    address _unlockVaultFeeTokenAddress;
    uint256 _unlockVaultFeeAmount;
    address _timeLockFeeTokenAddress;
    uint256 _timeLockFeeAmount;
    bool _collectUnlockFee;
    bool _collectTimeLockFee;
    address _nftAddress = address(0x5D37f5da50051d729Fc60E36EE493bBcddD1fb1c);
    bool _checkForNFT;
    address everRiseNFTStakeAddress = 0x23cD2E6b283754Fd2340a75732f9DdBb5d11807e;
    address everRiseAddress = 0xC17c30e98541188614dF99239cABD40280810cA3;



    constructor() Ownable(msg.sender) {

    }

    function setFeeAddress(address feeAddress) external onlyOwner {
        _feeAddress = feeAddress;
    }

    function setUnlockVaultFeeDetails(address feeToken, uint256 amount, uint256 fractionalDecimals) external onlyOwner {
        _unlockVaultFeeTokenAddress = feeToken;
        uint8 decimals = 18;
        if (feeToken != address(0)) {
            decimals = Metadata(feeToken).decimals();
        }
        _unlockVaultFeeAmount = (amount * 10**decimals) / 10 ** fractionalDecimals;
    }

    function setTimelockFeeDetails(address feeToken, uint256 amount, uint256 fractionalDecimals) external onlyOwner {
        _timeLockFeeTokenAddress = feeToken;
        uint8 decimals = 18;
        if (feeToken != address(0)) {
            decimals = Metadata(feeToken).decimals();
        }
        _timeLockFeeAmount = (amount * 10**decimals) / 10 ** fractionalDecimals;
    }

    function setCollectUnlockFee(bool unlock) external onlyOwner {
        _collectUnlockFee = unlock;
    }

    function setCollectTimelockFee(bool timelock) external onlyOwner {
        _collectTimeLockFee = timelock;
    }

    function setNFTAddress(address addr) external onlyOwner {
        _nftAddress = addr;
    }

    function setCheckForNFT(bool flag) external onlyOwner {
        _checkForNFT = flag;
    }

    function updateEverRiseInfo(address erAddress, address erStakeAddress) external onlyOwner {
        everRiseAddress = erAddress;
        everRiseNFTStakeAddress = erStakeAddress;
    }

    function getEverriseAddress() external view returns (address) {
        return everRiseAddress;
    }

    function getEverRiseNFTAddress() external view returns (address) {
        return everRiseNFTStakeAddress;
    }

    function getCheckForNFT() external view returns (bool) {
        return _checkForNFT;
    }

    function getNFTAddress() external view returns (address) {
        return _nftAddress;
    }

    function getFeeAddress() external view returns (address) {
        return _feeAddress;
    }

    function getUnlockVaultFeeTokenAddress() external view returns (address) {
        return _unlockVaultFeeTokenAddress;
    }

    function getUnlockVaultFeeAmount() external view returns (uint256) {
        return _unlockVaultFeeAmount;
    }

    function getCollectUnlockFee() external view returns (bool) {
        return _collectUnlockFee;
    }

    function getCollectTimelockFee() external view returns (bool) {
        return _collectTimeLockFee;
    }

    function getTimeLockFeeTokenAddress() external view returns (address) {
        return _timeLockFeeTokenAddress;
    }

    function getTimeLockFeeAmount() external view returns (uint256) {
        return _timeLockFeeAmount;
    }

}
