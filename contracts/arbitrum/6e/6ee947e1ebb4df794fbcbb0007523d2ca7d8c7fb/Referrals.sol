// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./IReferrals.sol";
import "./Ownable.sol";
import "./IERC721.sol";


contract Referrals is IReferrals, Ownable {
  event SetDiscounts(uint16 _rebateReferrer, uint16 _rebateReferrerVip, uint16 _discountReferee, uint16 _discountRefereeVip);
  event SetVip(address user, bool _isVip);
  event AddedVipNFT(address nft);
  event RemovedVipNFT(address nft);
  
  /// @notice Referrer names for user friendly referrer picking
  mapping (bytes32 => address) private _referrerNames;
  /// @notice Referee to referrer mapping
  mapping (address => address) private _refereeToReferrer;
  /// @notice Mapping of a user referees
  mapping (address => address[]) private _referrerToReferees;
  /// @notice Mapping of VIP users
  mapping (address => bool) private _vips;
  /// @notice Array of VIP NFTs / hold NFT to get VIP status
  address[] private vipNfts;
  
  /// @notice Referrer/referee discount in percent X4 (500 == 5%)
  uint16 public rebateReferrer = 500;
  uint16 public rebateReferrerVip = 800;
  uint16 public discountReferee = 500;
  uint16 public discountRefereeVip = 800;
  
  
  /// @notice Set referral fee discounts
  function setReferralDiscounts(uint16 _rebateReferrer, uint16 _rebateReferrerVip, uint16 _discountReferee, uint16 _discountRefereeVip) public onlyOwner {
    require(_rebateReferrer < 10000 && _rebateReferrerVip < 10000 && _discountReferee < 10000 && _discountRefereeVip < 10000, "GEC: Invalid Discount");
    rebateReferrer = _rebateReferrer;
    rebateReferrerVip = _rebateReferrerVip;
    discountReferee = _discountReferee;
    discountRefereeVip = _discountRefereeVip;
    emit SetDiscounts(_rebateReferrer, _rebateReferrerVip, _discountReferee, _discountRefereeVip);
  } 
  
  
  /// @notice Register a referral name
  function registerName(bytes32 name) public {
    require(_referrerNames[name] == address(0x0), "Already registered");
    _referrerNames[name] = msg.sender;
  }
  
  /// @notice Register a referrer by name
  function registerReferrer(bytes32 name) public {
    address referrer = _referrerNames[name];
    require(referrer != msg.sender, "Self refer");
    require(referrer != address(0x0), "No such referrer");
    require(_refereeToReferrer[msg.sender] == address(0x0), "Referrer already set");
    _refereeToReferrer[msg.sender] = referrer;
    _referrerToReferees[referrer].push(msg.sender);
  }
  
  /// @notice Get referrer
  function getReferrer(address user) public view returns (address referrer) {
    referrer = _refereeToReferrer[user];
  }
  
  /// @notice Get number of referees
  function getRefereesLength(address referrer) public view returns (uint length) {
    length = _referrerToReferees[referrer].length;
  }
  
  /// @notice Get referee by index
  function getReferee(address referrer, uint index) public view returns (address referee) {
    referee = _referrerToReferees[referrer][index];
  }
  

  /// @notice Get referral parameters
  function getReferralParameters(address user) external view returns (address _referrer, uint16 _rebateReferrer, uint16 _discountReferee) {
    _referrer = getReferrer(user);
    if (_referrer != address(0)){
      // If user has no referrer he doesnt get the discount for referees
      _discountReferee = isVip(user) ? discountRefereeVip : discountReferee;
      // the referrer discount is based on referrer status not user status
      _rebateReferrer = isVip(_referrer) ? rebateReferrerVip : rebateReferrer;
    }
  }
  
  
  ///// VIP 
  
  /// @notice Set or unset VIP user
  function setVip(address user, bool _isVip) public onlyOwner {
    _vips[user] = _isVip;
    emit SetVip(user, _isVip);
  }
  
  /// @notice Add VIP NFT to list
  function addVipNft(address _nft) public onlyOwner {
    require(_nft != address(0x0), "Ref: Invalid NFT");
    for (uint k; k < vipNfts.length; k++) require(_nft != vipNfts[k], "Ref: Already NFT");
    vipNfts.push(_nft);
    emit AddedVipNFT(_nft);
  }
  
  /// @notice Remove VIP NFT
  function removeVipNft(address _nft) public onlyOwner {
    for (uint k = 0; k < vipNfts.length; k++) {
      if (vipNfts[k] == _nft){
        if (k < vipNfts.length - 1) vipNfts[k] = vipNfts[vipNfts.length - 1];
        vipNfts.pop();
        emit RemovedVipNFT(_nft);
      }
    }
  }
  
  /// @notice Check if user is VIP or holds partner VIP NFT
  function isVip(address user) public view returns (bool) {
    if (_vips[user]) return true;
    for (uint k; k < vipNfts.length; k++) 
      if (IERC721(vipNfts[k]).balanceOf(user) > 0) return true;
    return false;
  }
  

}
