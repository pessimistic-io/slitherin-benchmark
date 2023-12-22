// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

interface IReferral {
    function BASIS_POINTS() external view returns(uint256);
    function setHandler(address _handler, bool _isActive) external;
    function setTier(uint256 _tierId, uint256 _totalRebate, uint256 _discountShare) external;
    function setReferrerTier(address _referrer, uint256 _tierId) external;
    function setTraderReferral(address _account, address _referrer) external;

    function getTraderReferralInfo(address _account) external returns(address, uint256, uint256);

    function calculateRebateAmount(address _account, uint256 _fee) external view returns(uint256);
    function rebate(address _token, address _account, uint256 _amount) external;
}

