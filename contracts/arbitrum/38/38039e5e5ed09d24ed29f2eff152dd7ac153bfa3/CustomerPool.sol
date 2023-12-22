// SPDX-License-Identifier: UNLICENSED

/// This contract is responsible for customer purchase records processing.

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./DataTypes.sol";

contract CustomerPool is Ownable, ReentrancyGuard {
    address public proxy;

    mapping(uint256 => mapping(uint256 => DataTypes.PurchaseProduct)) productPurchasePool;
    mapping(uint256 => uint256[]) productCount;

    constructor(address _proxy) {
        proxy = _proxy;
    }

    /**
     * notice Update the agency contract address.
     * @param _proxy Proxy contract address.
     */
    function updateProxy(address _proxy) public onlyOwner {
        proxy = _proxy;
    }

    /**
     * notice Update customerReward.
     * @param _pid Product id.
     * @param _customerId customerId.
     * @param _customerReward Reward.
     */
    function updateCustomerReward(
        uint256 _pid,
        uint256 _customerId,
        uint256 _customerReward
    ) external onlyProxy returns (bool) {
        productPurchasePool[_pid][_customerId].customerReward = _customerReward;
        return true;
    }

    /**
     * notice Add purchase record.
     * @param _pid Product id.
     * @param _customerAddress Customer's wallet address.
     * @param _amount Amount and quantity.
     * @param _token Token.
     * @param _customerReward Reward.
     * @param _cryptoQuantity The user ends up with the target coin.
     */
    function addCustomerByProduct(
        uint256 _pid,
        uint256 _customerId,
        address _customerAddress,
        uint256 _amount,
        address _token,
        uint256 _customerReward,
        uint256 _cryptoQuantity
    ) external onlyProxy returns (bool) {
        uint256 _releaseHeight = block.number;
        DataTypes.PurchaseProduct memory product = DataTypes.PurchaseProduct({
            customerId: _customerId,
            customerAddress: _customerAddress,
            amount: _amount,
            releaseHeight: _releaseHeight,
            tokenAddress: _token,
            customerReward: _customerReward,
            cryptoQuantity: _cryptoQuantity
        });

        productPurchasePool[_pid][_customerId] = product;
        productCount[_pid].push(_customerId);
        return true;
    }

    /**
     * notice Clears the specified purchase record.
     * @param _pid Product id.
     * @param _customerId Customer id.
     */
    function deleteSpecifiedProduct(uint256 _pid, uint256 _customerId) external onlyProxy returns (bool) {
        uint256[] storage customerIdList = productCount[_pid];
        delete productPurchasePool[_pid][_customerId];

        for (uint256 i = 0; i < customerIdList.length; i++) {
            if (_customerId == customerIdList[i]) {
                customerIdList[i] = customerIdList[customerIdList.length - 1];
                customerIdList.pop();
            }
        }
        return true;
    }

    function getSpecifiedProduct(
        uint256 _pid,
        uint256 _customerId
    ) public view returns (DataTypes.PurchaseProduct memory) {
        return productPurchasePool[_pid][_customerId];
    }

    function getProductList(uint256 _pid) public view returns (DataTypes.PurchaseProduct[] memory) {
        uint256[] memory customerIdList = productCount[_pid];
        DataTypes.PurchaseProduct[] memory prodList = new DataTypes.PurchaseProduct[](customerIdList.length);

        for (uint256 i = 0; i < customerIdList.length; i++) {
            prodList[i] = productPurchasePool[_pid][customerIdList[i]];
        }
        return prodList;
    }

    function getProductQuantity(uint256 _pid) public view returns (uint256) {
        return productCount[_pid].length;
    }

    function getUserProducts(
        uint256 _pid,
        address _customerAddress
    ) external view returns (DataTypes.PurchaseProduct[] memory) {
        uint256[] memory customerIdList = productCount[_pid];
        DataTypes.PurchaseProduct[] memory customerProdList = new DataTypes.PurchaseProduct[](customerIdList.length);
        for (uint256 i = 0; i < customerIdList.length; i++) {
            customerProdList[i] = productPurchasePool[_pid][customerIdList[i]];
        }
        uint256 count;
        for (uint256 i = 0; i < customerProdList.length; i++) {
            if (_customerAddress == customerProdList[i].customerAddress) {
                count++;
            }
        }
        DataTypes.PurchaseProduct[] memory list = new DataTypes.PurchaseProduct[](count);
        uint256 j;
        for (uint256 i = 0; i < customerProdList.length; i++) {
            if (_customerAddress == customerProdList[i].customerAddress) {
                list[j] = customerProdList[i];
                j++;
            }
        }
        return list;
    }

    modifier onlyProxy() {
        require(proxy == msg.sender, "Ownable: caller is not the proxy");
        _;
    }
}

