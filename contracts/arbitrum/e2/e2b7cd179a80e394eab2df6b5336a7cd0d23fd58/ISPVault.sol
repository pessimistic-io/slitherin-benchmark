// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./ILBPair.sol";
import "./ISPVFactory.sol";

interface ISPVault {
    event Deposited(ILBPair indexed pair, uint256 amountX, uint256 amountY, uint24 addedLow, uint24 addedUpper);

    event Withdrawn(ILBPair indexed pair, uint24 removedLow, uint24 removedUpper);

    event ManagerSet(address indexed manager);

    function getPair() external view returns (ILBPair);

    function getTokenX() external view returns (IERC20);

    function getTokenY() external view returns (IERC20);

    function getRange() external view returns (uint24 low, uint24 upper);

    function getManager() external view returns (address);

    function getFactory() external view returns (ISPVFactory);

    function getCollectableFees() external view returns (uint256 amountX, uint256 amountY);

    function previewWithdraw(uint24 removedLow, uint24 removedUpper)
        external
        view
        returns (uint256 amountX, uint256 amountY);

    function deposit(uint256 amountX, uint256 amountY, uint24 addedLow, uint24 addedUpper) external;

    function withdraw(uint24 removedLow, uint24 removedUpper) external;

    function collectFees() external;

    function setManager(address manager) external;

    function execute(address target, uint256 value, bytes memory data) external;
}

