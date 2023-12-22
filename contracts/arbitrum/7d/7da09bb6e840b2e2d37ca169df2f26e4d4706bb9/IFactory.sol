
pragma solidity >=0.5.0;

interface IFactory {
    function mintFee() external view returns (uint256);
    function bridgeFee() external view returns (uint256);
    function feeReceiver() external view returns (address);
} 
