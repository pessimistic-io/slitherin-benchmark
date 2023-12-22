// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface INftMinning {
    function checkTax(uint uid_) external view returns (uint _tax);

    function checkGeTax(uint uid_) external view returns (uint _tax);

    function checkDaoBonus(uint uid_) external view returns (uint _bonus);

    function unionOwner(address) external view returns (uint);

    function checkUserKunIdList(address) external view returns (uint[] memory);

    function checkUserUnions(address) external view returns (uint);

    function checkUserReward(address user_) external view returns (uint);

    function checkUnionLv(uint uid_) external view returns (uint);

    function kunInfo(
        uint kunId_ // nft owner
    )
        external
        view
        returns (
            address owner,
            // nft token id
            uint kunId,
            // the power of amplification
            uint kunPower,
            uint depositTime
        );

    function unionsInfo(
        uint uid_ // union owner
    )
        external
        view
        returns (
            address owner,
            // union level
            uint lv,
            // union id is nft token id
            uint unionId,
            // invitation union
            uint topUnions,
            // how many people in this union
            uint members,
            // claimed tax
            uint tax,
            // total tax
            uint taxDebt,
            // claimed getax
            uint geTax,
            // total getax
            uint geTaxDebt,
            // claimed dao bonus
            uint dao,
            // this value is increased when a union is upgraded
            uint daoToClaim,
            // debt
            uint daoDebt
        );

    function userInfo(
        address
    )
        external
        view
        returns (
            // the union to which this user belongs
            uint unionsId,
            // the user total power, accrual of all nft
            uint power,
            // this value is increased when a nft is deposited
            uint toClaim,
            // user claimed Token
            uint claimed,
            // debt of user, it should update after gobal debt
            uint debt,
            // Time of last interaction with the contract
            uint lastTime
        );
}

