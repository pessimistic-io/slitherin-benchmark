pragma solidity ^0.8.12;

interface ICapPool {
    function UNIT (  ) external view returns ( uint256 );
    function creditUserProfit ( address destination, uint256 amount ) external;
    function currency (  ) external view returns ( address );
    function deposit ( uint256 amount ) external;
    function getBalance ( address account ) external view returns ( uint256 );
    function getCurrencyBalance ( address account ) external view returns ( uint256 );
    function getUtilization (  ) external view returns ( uint256 );
    function maxCap (  ) external view returns ( uint256 );
    function minDepositTime (  ) external view returns ( uint256 );
    function openInterest (  ) external view returns ( uint256 );
    function owner (  ) external view returns ( address );
    function rewards (  ) external view returns ( address );
    function router (  ) external view returns ( address );
    function setOwner ( address newOwner ) external;
    function setParams ( uint256 _minDepositTime, uint256 _utilizationMultiplier, uint256 _maxCap, uint256 _withdrawFee ) external;
    function setRouter ( address _router ) external;
    function totalSupply (  ) external view returns ( uint256 );
    function trading (  ) external view returns ( address );
    function updateOpenInterest ( uint256 amount, bool isDecrease ) external;
    function utilizationMultiplier (  ) external view returns ( uint256 );
    function withdraw ( uint256 currencyAmount ) external;
    function withdrawFee (  ) external view returns ( uint256 );
}

