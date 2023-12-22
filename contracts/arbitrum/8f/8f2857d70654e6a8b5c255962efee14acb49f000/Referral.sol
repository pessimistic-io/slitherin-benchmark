// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./IReferral.sol";
import "./TransferHelper.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20.sol";
import "./EnumerableSet.sol";

contract Referral is Initializable,OwnableUpgradeable, IReferral {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct Tier {
        uint256 totalRebate;
        uint256 discountShare;
    }

    uint256 public override constant BASIS_POINTS = 10000;

    mapping (address => uint256) public referrerDiscountShares;
    mapping (address => uint256) public referrerTiers;
    mapping (uint256 => Tier) public tiers;

    mapping (address => bool) public isHandler;

    mapping (address => address) public traderReferrers;
    
    address public dlp;
    uint256 public minBalance;

    mapping (address => EnumerableSet.AddressSet) private referrerTraders;

    event SetHandler(address handler, bool isActive);
    event SetTraderReferral(address account, address referrer);
    event SetTier(uint256 tierId, uint256 totalRebate, uint256 discountShare);
    event SetReferrerTier(address referrer, uint256 tierId);
    event SetReferrerDiscountShare(address referrer, uint256 discountShare);
    event Rebate(
        address trader, 
        address referrer, 
        address token,
        uint256 totalAmount,
        uint256 discountAmount,
        uint256 rebateAmount
    );

    modifier onlyHandler() {
        require(isHandler[msg.sender], "Referral: forbidden");
        _;
    }

    function initialize(address _dlp,uint256 _minBalance) public initializer {
        __Ownable_init();
        dlp = _dlp;
        minBalance = _minBalance;
    }
    function setDlp(address _dlp) external onlyOwner{
        dlp = _dlp;
    }
    function setMinBalance(uint256 _minBalance) external onlyOwner{
        minBalance = _minBalance;
    }

    function setHandler(address _handler, bool _isActive) external override onlyOwner {
        isHandler[_handler] = _isActive;
        emit SetHandler(_handler, _isActive);
    }

    function setTier(uint256 _tierId, uint256 _totalRebate, uint256 _discountShare) external override onlyOwner {
        require(_totalRebate <= BASIS_POINTS, "Referral: invalid totalRebate");
        require(_discountShare <= BASIS_POINTS, "Referral: invalid discountShare");

        Tier memory tier = tiers[_tierId];
        tier.totalRebate = _totalRebate;
        tier.discountShare = _discountShare;
        tiers[_tierId] = tier;
        emit SetTier(_tierId, _totalRebate, _discountShare);
    }

    function setReferrerTier(address _referrer, uint256 _tierId) external override onlyOwner {
        referrerTiers[_referrer] = _tierId;
        emit SetReferrerTier(_referrer, _tierId);
    }

    function setReferrerDiscountShare(uint256 _discountShare) external {
        require(_discountShare <= BASIS_POINTS, "Referral: invalid discountShare");

        referrerDiscountShares[msg.sender] = _discountShare;
        emit SetReferrerDiscountShare(msg.sender, _discountShare);
    }

    function setTraderReferralByUser(address _referrer) external {
        _setTraderReferral(msg.sender, _referrer);
    }

    function setTraderReferral(address _account, address _referrer) external override onlyHandler {
        _setTraderReferral(_account, _referrer);
    }

    function getTraderReferralInfo(
        address _account
    ) public override view returns(address, uint256, uint256) {
        address referrer = traderReferrers[_account];
        if(referrer == address(0)){
            return (address(0), 0, 0);
        }
        uint256 tierId = referrerTiers[referrer];
        Tier memory tier = tiers[tierId];
        uint256 discountShare = tier.discountShare;
        if(referrerDiscountShares[referrer] > 0){
            discountShare = referrerDiscountShares[referrer];
        }
        return (referrer, tier.totalRebate, discountShare);
    }

    function affiliateCount(address _referrer) public view returns(uint256){
        return referrerTraders[_referrer].length();
    }
    function affiliateAt(address _referrer, uint256 _index) public view returns(address){
        return referrerTraders[_referrer].at(_index);
    }
    function affiliates(address _referrer) public view returns(address[] memory){
        return referrerTraders[_referrer].values();
    }

    function validate(address _account) public view returns(bool){
        if(dlp != address(0)){
            if(IERC20(dlp).balanceOf(_account) < minBalance){
                return false;
            }
        }

        return true;
    }

    function calculateRebateAmount(address _account, uint256 _fee) public override view returns(uint256){
        (
            address referrer,
            uint256 totalRebate,
            /*uint256 discountShare*/
        ) = getTraderReferralInfo(_account);
        if(referrer == address(0)){
            return 0;
        }
        
        if(!validate(referrer)){
            return 0;
        }
        
        return _fee * totalRebate / BASIS_POINTS;
    }

    function rebate(address _token, address _account, uint256 _amount) public override{
        require(_token != address(0), "Referral: invalid token");
        if(_amount == 0){
            return;
        }
        (
            address referrer,
            /*uint256 totalRebate*/,
            uint256 discountShare
        ) = getTraderReferralInfo(_account);
        if(referrer == address(0)){
            return;
        }
        if(!validate(referrer)){
            return;
        }

        uint256 discountAmount = _amount * discountShare / BASIS_POINTS;
        if(discountAmount>0){
            TransferHelper.safeTransfer(_token, _account, discountAmount);
        }
        uint256 rebateAmount = _amount - discountAmount;
        if(rebateAmount > 0){
            TransferHelper.safeTransfer(_token, referrer, rebateAmount);
        }

        emit Rebate(_account, referrer, _token, _amount, discountAmount, rebateAmount);

    }

    function _setTraderReferral(address _account, address _referrer) private {
        require(_account != _referrer, "Referral: refer to self");
        require(_account!=address(0), "Referral: refer to zero address");
        
        if(traderReferrers[_account] != address(0)){
            EnumerableSet.AddressSet storage preReferrerTraders = referrerTraders[traderReferrers[_account]];
            preReferrerTraders.remove(_account);
        }

        EnumerableSet.AddressSet storage traders = referrerTraders[_referrer];
        traders.add(_account);
        traderReferrers[_account] = _referrer;

        emit SetTraderReferral(_account, _referrer);
    }
}

