// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IERC721Enumerable.sol";

interface IFortunatemon is IERC721Enumerable{

    enum Phase {
        AIRDROP,
        ONE_SALE,
        SECOND_SALE
    }

    function cap() external view virtual returns(uint);

    function airdropCap() external view virtual returns(uint);

    function firstSaleCap() external view virtual returns(uint);

    function perSaleCap() external view virtual returns(uint);

    function phase() external view virtual returns(Phase);

    function fee() external view virtual returns(uint);

    function feeTo() external view virtual returns(address);

    function tokenBaseURI() external view virtual returns(string memory);

    function userAirdropped(address user) external view virtual returns(bool);

    function phaseMined(Phase phase) external view virtual returns(uint);

    function batchSale(uint count) external virtual;

    function perSaleable() external view virtual returns(uint);
}
