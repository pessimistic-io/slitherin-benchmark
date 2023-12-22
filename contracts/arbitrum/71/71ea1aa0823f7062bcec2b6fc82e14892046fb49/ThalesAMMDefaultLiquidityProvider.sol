// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./SafeERC20Upgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./ProxyOwned.sol";
import "./ProxyPausable.sol";
import "./ProxyReentrancyGuard.sol";

contract ThalesAMMDefaultLiquidityProvider is ProxyOwned, Initializable, ProxyReentrancyGuard {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public sUSD;

    uint private constant MAX_APPROVAL = type(uint256).max;

    /// @return the adddress of the AMMLP contract
    address public liquidityPool;

    //    /// @custom:oz-upgrades-unsafe-allow constructor
    //    constructor() {
    //        _disableInitializers();
    //    }

    function initialize(
        address _owner,
        IERC20Upgradeable _sUSD,
        address _thalesAMMLiquidityPool
    ) public initializer {
        setOwner(_owner);
        initNonReentrant();
        sUSD = _sUSD;
        liquidityPool = _thalesAMMLiquidityPool;
        sUSD.approve(liquidityPool, MAX_APPROVAL);
    }

    /// @notice Setting the ThalesAMMLiquidityPool
    /// @param _thalesAMMLiquidityPool Address of Staking contract
    function setThalesAMMLiquidityPool(address _thalesAMMLiquidityPool) external onlyOwner {
        if (liquidityPool != address(0)) {
            sUSD.approve(liquidityPool, 0);
        }
        liquidityPool = _thalesAMMLiquidityPool;
        sUSD.approve(_thalesAMMLiquidityPool, MAX_APPROVAL);
        emit SetThalesAMMLiquidityPool(_thalesAMMLiquidityPool);
    }

    function retrieveSUSDAmount(address payable account, uint amount) external onlyOwner nonReentrant {
        sUSD.safeTransfer(account, amount);
    }

    event SetThalesAMMLiquidityPool(address _thalesAMMLiquidityPool);
}

