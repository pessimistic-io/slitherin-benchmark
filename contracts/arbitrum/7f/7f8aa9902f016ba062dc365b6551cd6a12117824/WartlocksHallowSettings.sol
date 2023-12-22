//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./WartlocksHallowContracts.sol";

abstract contract WartlocksHallowSettings is Initializable, WartlocksHallowContracts {

    function __WartlocksHallowSettings_init() internal initializer {
        WartlocksHallowContracts.__WartlocksHallowContracts_init();
    }

    function toggleHouseDesignComplete() external onlyAdminOrOwner {
        isHouseDesignComplete = !isHouseDesignComplete;

        emit HouseDesignCompleteChanged(isHouseDesignComplete);
    }

    function setNumberItemsToBurn(uint256 _numberItemsToBurn) external onlyAdminOrOwner {
        numberItemsToBurn = _numberItemsToBurn;
        emit ItemsToBurnChanged(numberItemsToBurn);
    }
}
