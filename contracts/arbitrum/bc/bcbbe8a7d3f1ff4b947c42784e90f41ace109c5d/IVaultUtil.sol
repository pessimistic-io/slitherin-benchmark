// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;
import "./IVault.sol";

interface IVaultUtil {
    function updateGlobalData(IVault.UpdateGlobalDataParams memory p) external;

    function updateGlobal(
        address _indexToken,
        uint256 price,
        uint256 _sizeDelta,
        bool _isLong,
        bool _increase,
        uint256 _insurance
    ) external;

    function getLPPrice() external view returns (uint256);
}

