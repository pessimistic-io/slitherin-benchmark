// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {ERC20} from "./ERC20.sol";
import {IERC20} from "./IERC20.sol";
import {IOracle} from "./IOracle.sol";
import {IPairUniV2} from "./IPairUniV2.sol";
import {IRouterUniV2} from "./IRouterUniV2.sol";
import {IRewarderMiniChefV2} from "./IRewarderMiniChefV2.sol";

contract VaultSushiLP is ERC20 {
    error TransferFailed();

    IRewarderMiniChefV2 public rewarder; // MiniChefV2
    IRouterUniV2 public router; // UniswapV2Router02
    IPairUniV2 public asset; // UniswapV2Pair
    uint256 poolId;
    address[] public path0;
    address[] public path1;

    constructor(
        address _rewarder,
        address _router,
        uint256 _poolId,
        address[] memory _path0,
        address[] memory _path1
    )
        ERC20("SushiLP Vault", "vSLP", 18)
    {
        rewarder = IRewarderMiniChefV2(_rewarder);
        router = IRouterUniV2(_router);
        asset = IPairUniV2(rewarder.lpToken(poolId));
        poolId = _poolId;
        path0 = _path0;
        path1 = _path1;
    }

    function mint(uint256 amt, address usr) external returns (uint256) {
        earn();
        _pull(address(asset), msg.sender, amt);
        uint256 tma = totalManagedAssets();
        uint256 sha = tma == 0 ? amt : amt * totalSupply / tma;
        IERC20(address(asset)).approve(address(rewarder), amt);
        rewarder.deposit(poolId, amt, address(this));
        _mint(sha, usr);
        return sha;
    }

    function burn(uint256 sha, address usr) external returns (uint256) {
        earn();
        if (balanceOf[msg.sender] < sha) revert InsufficientBalance();
        uint256 tma = totalManagedAssets();
        uint256 amt = sha * tma / totalSupply;
        _burn(sha, msg.sender);
        rewarder.withdraw(poolId, amt, address(this));
        _push(address(asset), usr, amt);
        return amt;
    }

    function earn() public {
        rewarder.harvest(poolId, address(this));
        uint256 amt = IERC20(rewarder.SUSHI()).balanceOf(address(this));
        uint256 haf = amt / 2;
        if (amt == 0) return;
        if (path0.length > 0) {
          router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
              haf,
              0, // TODO fix using oracle
              path0,
              address(asset),
              type(uint256).max
          );
        }
        if (path1.length > 0) {
          router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
              amt - haf,
              0, // TODO fix using oracle
              path1,
              address(asset),
              type(uint256).max
          );
        }
        asset.mint(address(this));
        asset.skim(address(this));
        uint256 liq = IERC20(address(asset)).balanceOf(address(this));
        rewarder.deposit(poolId, liq, address(this));
    }

    function totalManagedAssets() public view returns (uint256) {
        (uint256 amt,) = rewarder.userInfo(poolId, address(this));
        return amt;
    }

    function _pull(address tkn, address usr, uint256 amt) internal {
        if (!IERC20(tkn).transferFrom(usr, address(this), amt)) revert
            TransferFailed();
    }

    function _push(address tkn, address usr, uint256 amt) internal {
        if (!IERC20(tkn).transfer(usr, amt)) revert TransferFailed();
    }
}

