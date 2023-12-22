// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Storage
 * @dev 存储和检索一个变量值
 */
contract Storage {

    uint256 number;

    /**
     * @dev 存储一个变量
     * @param num 存储num
     */
    function store(uint256 num) public {
        number = num;
    }

    /**
     * @dev 返回值
     * @return 'number'的值
     */
    function retrieve() public view returns (uint256){
        return number;
    }
}

