// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;
import "./DataTypes.sol";

interface ICustomerPool {
    function deleteSpecifiedProduct(uint256 _prod, uint256 _customerId) external returns (bool);

    function addCustomerByProduct(
        uint256 _pid,
        uint256 _customerId,
        address _customerAddress,
        uint256 _amount,
        address _token,
        uint256 _customerReward,
        uint256 _cryptoQuantity
    ) external returns (bool);

    function updateCustomerReward(uint256 _pid, uint256 _customerId, uint256 _customerReward) external returns (bool);

    function getProductList(uint256 _prod) external view returns (DataTypes.PurchaseProduct[] memory);

    function getSpecifiedProduct(
        uint256 _pid,
        uint256 _customerId
    ) external view returns (DataTypes.PurchaseProduct memory);
}

