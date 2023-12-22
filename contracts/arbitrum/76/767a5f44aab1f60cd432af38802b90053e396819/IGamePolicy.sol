// SPDX-License-Identifier: MIT

pragma solidity =0.8.17;
pragma experimental ABIEncoderV2;

interface IGamePolicy {
    function setOperator(address, bool) external;
    function isOperator(address) external view returns (bool);
    function getOperators() external view returns (address[] memory);
    function setTournamentRouter(address, bool) external;
    function isTournamentRouter(address) external view returns (bool);
    function getTournamentRouters() external view returns (address[] memory);
    function isHeadsUpBank(address) external view returns(bool);
    function setHeadsUpBank(address) external;
    function isHeadsUpRouter(address) external view returns (bool);
    function setHeadsUpRouter(address, bool) external;
    function getBankAddress() external view returns (address);
    function getTreasuryAddress() external view returns (address);
    function getJackpotAddress() external view returns (address);
    function isTargetToken(address) external view returns (bool);
    function isBuyInToken(address) external view returns (bool);
    function getSponsorLimit(address) external view returns (uint256);
    function getBuyInLimit(address) external view returns (uint256);
    function isPrizeManager(address) external view returns (bool);
}
