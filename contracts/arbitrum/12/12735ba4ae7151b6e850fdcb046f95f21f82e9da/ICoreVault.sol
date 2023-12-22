// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC4626} from "./ERC4626.sol";

interface ICoreVault is IERC4626 {
    function setVaultRouter(address vaultRouter) external;

    function setLpFee(bool isBuy, uint256 fee) external;

    function sellLpFee() external view returns (uint256);

    function buyLpFee() external view returns (uint256);

    function setCooldownDuration(uint256 duration) external;

    function computationalCosts(
        bool isBuy,
        uint256 amount
    ) external view returns (uint256);

    function transferOutAssets(address to, uint256 amount) external;

    function getLPFee(bool isBuy) external view returns (uint256);

    function setIsFreeze(bool f) external;

    /* function initialize(
        address _asset,
        string memory _name,
        string memory _symbol,
        address _vaultRouter,
        address
    ) external; */
}

