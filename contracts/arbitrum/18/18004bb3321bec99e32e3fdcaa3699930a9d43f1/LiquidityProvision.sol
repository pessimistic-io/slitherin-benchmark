//SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./access_AccessControl.sol";
import "./SafeERC20.sol";

import "./FixedPointMathLib.sol";

import {Cast} from "./Cast.sol";
import {ILadle} from "./ILadle.sol";
import {IPool} from "./IPool.sol";

import "./Balanceless.sol";

contract YieldLiquidityProvision is AccessControl, Balanceless {
    using Cast for *;
    using FixedPointMathLib for *;
    using SafeERC20 for *;

    address public immutable treasury;
    ILadle public immutable ladle;

    constructor(ILadle _ladle, address _treasury) {
        ladle = _ladle;
        treasury = _treasury;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function provideLiquidity(IPool pool, bytes6 seriesId, bytes6 baseId, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        (uint256 baseInPool, uint256 fyTokenInPool,,) = pool.getCache();
        fyTokenInPool -= pool.totalSupply();

        uint256 baseToPool = baseInPool.mulDivUp(amount, baseInPool + fyTokenInPool);
        uint256 fyTokenToPool = amount - baseToPool;

        IERC20 asset = IERC20(address(pool.base()));
        if (fyTokenToPool > 0) {
            (bytes12 vaultId,) = ladle.build(seriesId, baseId, 0);

            asset.safeTransferFrom(treasury, address(ladle.joins(baseId)), fyTokenToPool);
            ladle.pour(vaultId, address(pool), fyTokenToPool.i128(), fyTokenToPool.i128());
        }

        asset.safeTransferFrom(treasury, address(pool), baseToPool);

        pool.mint({
            to: treasury,
            remainder: treasury,
            minRatio: 0, // TODO: set min ratio
            maxRatio: type(uint256).max // TODO: set max ratio
        });
    }

    function collectBalance(address token, address payable to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _collectBalance(ERC20(token), to, amount);
    }
}

