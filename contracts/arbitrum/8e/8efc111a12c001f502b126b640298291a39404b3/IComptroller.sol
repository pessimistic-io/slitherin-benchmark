// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;


interface IComptroller {
    function claimComp(address holder, address[] memory cTokens) external;

    function claimComp(
        address[] memory holders,
        address[] memory cTokens,
        bool borrowers,
        bool suppliers
    ) external;

    function claimComp(address holder) external;

}
