pragma solidity 0.8.18;

interface IReferralController {
    function updateFee(address _trader, uint256 _value) external;
    function setReferrer(address _trader, address _referrer) external;
    function setPoolHook(address _poolHook) external;
    function setOrderHook(address _orderHook) external;
}

