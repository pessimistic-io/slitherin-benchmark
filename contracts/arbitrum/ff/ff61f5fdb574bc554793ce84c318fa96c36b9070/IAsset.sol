// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.5;

import "./Initializable.sol";
import "./Ownable.sol";
import "./IERC20.sol";

interface IAsset is IERC20 {
    function underlyingTokenBalance() external view returns (uint256);

    function decimals() external view returns (uint8);

    function cash() external view returns (uint120);

    function underlyingTokenDecimals() external view returns (uint8);

    function totalSupply() external view returns (uint256 ) ;
}
