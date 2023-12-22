// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.7.5;

import "./IERC20.sol";

interface IsPana is IERC20 {
    function rebase( uint256 panaProfit_, uint epoch_) external returns (uint256);

    function circulatingSupply() external view returns (uint256);

    function gonsForBalance( uint amount ) external view returns ( uint );

    function balanceForGons( uint gons ) external view returns ( uint );

    function index() external view returns ( uint );

    function toKARSHA(uint amount) external view returns (uint);

    function fromKARSHA(uint amount) external view returns (uint);
    
}

