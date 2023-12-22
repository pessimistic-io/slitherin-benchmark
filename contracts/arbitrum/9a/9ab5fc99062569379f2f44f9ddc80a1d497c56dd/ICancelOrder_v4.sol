pragma solidity 0.4.26;

interface ICancelOrder_v4 {
    function getOrderStatus(bytes32 _hash) external view returns (bool);
}
