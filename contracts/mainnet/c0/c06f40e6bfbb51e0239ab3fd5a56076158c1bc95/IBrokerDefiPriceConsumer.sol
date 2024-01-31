// SPDX-License-Identifier: MIT
// author : zainamroti
pragma solidity ^0.8.7;

interface IBrokerDefiPriceConsumer {
    function getPartnerPriceInEth() external view returns (uint);

    function getProPriceInEth() external view returns (uint);
}

