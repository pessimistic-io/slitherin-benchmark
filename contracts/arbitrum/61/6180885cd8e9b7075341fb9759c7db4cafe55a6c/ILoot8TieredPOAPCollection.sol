// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

interface ILoot8TieredPOAPCollection {

    event CouponAddedToTier(uint256 _tier, address _coupon);
    event CouponRemovedFromTier(uint256 _tier, address _coupon);
    event SetTier(string _name, uint256 _tier, string _tokenURI);

    function setTier( string memory _name, string memory _tokenURI) external;

    function addCouponForTier(uint256 _tier, address _coupon) external;

    function removeCouponForTier(uint256 _tier, address _coupon) external;

    function isCouponFromTier(uint256 _tier, address _coupon) external view returns(bool);

    function getTiersForPatron(address _patron) external view returns(uint256[] memory _tiers);

    function getEligibleCouponsForPatron(address _patron) external view returns(address[] memory _coupons);

    function isValidCoupon(address _coupon) external view returns(bool);

    function setCouponAirdroppedForToken(uint256 _tokenId) external;

    function checkCouponAirdroppedForToken(uint256 _tokenId, address _coupon) external view returns(bool);

}
