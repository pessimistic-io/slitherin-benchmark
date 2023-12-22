// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.5.0;

interface IOasisSwapFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function migrator() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function mevControlPre(address sender) external;
    function mevControlPost(address sender) external;
    function setFeeTo(address) external;
    function setMigrator(address) external;

    function setFee(uint64 _fee, uint64 _oasisFeeProportion) external;
    function setFeeManager(address manager, bool _isFeeManager) external;
    function isFeeManager(address manager) external view returns (bool);
    function isRebateApprovedRouter(address router) external view returns (bool);
    function rebateManager() external view returns (address);

    function pairCodeHash() external pure returns (bytes32);
}

