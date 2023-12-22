// contracts/GLDToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";
import "./Math.sol";
import "./console.sol";
import "./ComponentTreasuryEth.sol";
import "./ComponentTreasuryErc20.sol";

struct PresaleAddressInfo {
    bool whitelisted;
    bool claimed;
    uint256 paidEth;
}

contract ComponentPresale is Ownable {
    uint256 public presaleMaxWalletAllocationEth;
    uint256 public presaleMaxWalletAllocationTokens;
    uint256 public presaleMaxTotalAmountEth;

    uint256 public totalPaidEth;
    bool public isPurchaseWithoutWlAllowed;
    bool public isNoLimitPurchaseAllowed;
    bool public isClaimingAllowed;

    mapping(address => PresaleAddressInfo) purchaseInfo;

    ComponentTreasuryErc20 treasuryToken;
    ComponentTreasuryEth treasuryEth;

    constructor(
        address _addressManagedToken,
        uint256 _maxAllocationValue,
        uint256 _maxTokensPerAllocation,
        uint256 _presaleMaxTotalAmountEth
    ) {
        treasuryEth = new ComponentTreasuryEth();
        treasuryToken = new ComponentTreasuryErc20(_addressManagedToken);
        presaleMaxWalletAllocationEth = _maxAllocationValue;
        presaleMaxWalletAllocationTokens = _maxTokensPerAllocation;
        presaleMaxTotalAmountEth = _presaleMaxTotalAmountEth;
    }

    event Claimable();
    event Purchased(address _sender);

    function treasuryTokenAddress() public view returns (address) {
        return address(treasuryToken);
    }

    function treasuryEthAddress() public view returns (address) {
        return address(treasuryEth);
    }

    function totalPurchasedTokens() public view returns (uint256) {
        return (totalPaidEth * presaleMaxWalletAllocationTokens) / presaleMaxWalletAllocationEth;
    }

    function isWhitelisted(address _address) public view returns (bool) {
        return purchaseInfo[_address].whitelisted;
    }

    function isClaimed(address _address) public view returns (bool) {
        return purchaseInfo[_address].claimed;
    }

    function purchasedAmountEth(address _address) public view returns (uint256) {
        return purchaseInfo[_address].paidEth;
    }

    function addPresaleWhitelist(address[] memory _addresses, bool _enabled) public onlyOwner {
        for (uint n = 0; n < _addresses.length; n++) {
            purchaseInfo[_addresses[n]].whitelisted = _enabled;
        }
    }

    function allowPurchasesWithoutWhitelist(bool _allowWithoutWL) public onlyOwner {
        isPurchaseWithoutWlAllowed = _allowWithoutWL;
    }

    function allowPurchasesWithoutLimits(bool _allowWithoutLimits) public onlyOwner {
        isNoLimitPurchaseAllowed = _allowWithoutLimits;
    }

    function allowClaiming(bool _allowClaiming) public onlyOwner {
        isClaimingAllowed = _allowClaiming;
        emit Claimable();
    }

    function withdrawCollectedEth() public onlyOwner {
        treasuryEth.transferTo(msg.sender, treasuryEth.treasuryBalance());
    }

    function depositPresaleTokens(uint256 _amount) public onlyOwner {
        treasuryToken.managedToken().transferFrom(msg.sender, address(treasuryToken), _amount);
    }

    function withdrawUnsoldTokens(address _target) public onlyOwner {
        treasuryToken.transferTo(_target, treasuryToken.treasuryBalance());
    }

    function purchase() public payable {
        PresaleAddressInfo memory presaleInfo = purchaseInfo[msg.sender];

        require(isPurchaseWithoutWlAllowed || presaleInfo.whitelisted, "Not whitelisted, wait for public round");
        require(totalPaidEth + msg.value <= presaleMaxTotalAmountEth, "Can't buy more than total presale cap");
        require(
            presaleInfo.paidEth + msg.value <= presaleMaxWalletAllocationEth || isNoLimitPurchaseAllowed,
            "Can't buy more than max allocation"
        );

        presaleInfo.paidEth += msg.value;
        purchaseInfo[msg.sender] = presaleInfo;
        totalPaidEth += msg.value;
        treasuryEth.deposit{value: msg.value}();

        emit Purchased(msg.sender);
    }

    function claim() public {
        require(isClaimingAllowed, "Claim not allowed");

        PresaleAddressInfo memory presaleInfo = purchaseInfo[msg.sender];

        require(presaleInfo.paidEth > 0, "No presale purchased");
        require(!presaleInfo.claimed, "Already claimed");

        uint256 purchasedTokens = (presaleInfo.paidEth * presaleMaxWalletAllocationTokens) /
            presaleMaxWalletAllocationEth;

        treasuryToken.transferTo(msg.sender, purchasedTokens);
        presaleInfo.claimed = true;
        purchaseInfo[msg.sender] = presaleInfo;
    }

    receive() external payable {}
}

