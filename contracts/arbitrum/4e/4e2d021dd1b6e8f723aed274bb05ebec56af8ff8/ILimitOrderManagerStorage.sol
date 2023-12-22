// (c) 2023 Primex.finance
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.18;

import {IAccessControl} from "./IAccessControl.sol";

import {IPrimexDNS} from "./IPrimexDNS.sol";
import {ITraderBalanceVault} from "./ITraderBalanceVault.sol";
import {IPositionManager} from "./IPositionManager.sol";
import {ISwapManager} from "./ISwapManager.sol";

interface ILimitOrderManagerStorage {
    function ordersId() external view returns (uint256);

    function orderIndexes(uint256) external view returns (uint256);

    function traderOrderIndexes(uint256) external view returns (uint256);

    function traderOrderIds(address _trader, uint256 _index) external view returns (uint256);

    function bucketOrderIndexes(uint256) external view returns (uint256);

    function bucketOrderIds(address _bucket, uint256 _index) external view returns (uint256);

    function registry() external view returns (IAccessControl);

    function traderBalanceVault() external view returns (ITraderBalanceVault);

    function primexDNS() external view returns (IPrimexDNS);

    function pm() external view returns (IPositionManager);

    function swapManager() external view returns (ISwapManager);
}

