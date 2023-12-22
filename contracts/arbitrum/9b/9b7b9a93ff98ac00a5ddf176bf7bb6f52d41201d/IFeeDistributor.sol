pragma solidity 0.8.16;

interface IFeeDistributor {
    function depositFee(address _token, uint256 _amount) external;
}

