// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IERC20} from "./IERC20.sol";
import {IPairUniV2} from "./IPairUniV2.sol";
import {IOracle} from "./IOracle.sol";
import {IVault} from "./IVault.sol";
import {Strategy} from "./Strategy.sol";


contract StrategySushiswap is Strategy {
    string public name;
    IVault public vault;
    IOracle public oracleToken0; // Chainlink for pool token0
    IOracle public oracleToken1; // Chainlink for pool token1

    constructor(
        address _asset,
        address _investor,
        string memory _name,
        address _vault,
        address _oracleToken0,
        address _oracleToken1
    )
        Strategy(_asset, _investor)
    {
        name = _name;
        vault = IVault(_vault);
        oracleToken0 = IOracle(_oracleToken0);
        oracleToken1 = IOracle(_oracleToken1);
    }

    function getPair() private view returns (IPairUniV2) {
        return IPairUniV2(vault.asset());
    }

    function rate(uint256 sha) external view override returns (uint256) {
        IPairUniV2 pair = getPair();
        uint256 value = 0;
        uint256 lpTotalSupply = pair.totalSupply();
        uint256 lpAmount = vault.totalManagedAssets();
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        {
            uint256 decimals = uint256(IERC20(pair.token0()).decimals());
            uint256 price = uint256(oracleToken0.latestAnswer());
            value += ((((uint256(reserve0) * 1e12) / (10 ** decimals)) * lpAmount) / lpTotalSupply)
              * price / 1e14;
        }
        {
            uint256 decimals = uint256(IERC20(pair.token1()).decimals());
            uint256 price = uint256(oracleToken1.latestAnswer());
            value += ((((uint256(reserve1) * 1e12) / (10 ** decimals)) * lpAmount) / lpTotalSupply)
              * price / 1e14;
        }
        return value * sha / totalShares;
    }

    function _mint(uint256 amt) internal override returns (uint256) {
        IPairUniV2 pair = getPair();
        uint256 halfA = amt / 2;
        if (pair.token0() == address(asset)) {
            uint256 halfB = _swap1(pair, amt - halfA);
            _push(pair.token0(), address(pair), halfA);
            _push(pair.token1(), address(pair), halfB);
        } else {
            uint256 halfB = _swap0(pair, amt - halfA);
            _push(pair.token1(), address(pair), halfA);
            _push(pair.token0(), address(pair), halfB);
        }
        pair.mint(address(this));
        pair.skim(address(this));
        uint256 liq = IERC20(address(pair)).balanceOf(address(this));
        IERC20(address(pair)).approve(address(vault), liq);
        uint256 before = IERC20(address(vault)).balanceOf(address(this));
        vault.mint(liq, address(this));
        return IERC20(address(vault)).balanceOf(address(this)) - before;
    }

    function _burn(uint256 sha) internal override returns (uint256) {
        IPairUniV2 pair = getPair();
        vault.burn(sha, address(pair));
        pair.burn(address(this));
        if (pair.token0() == address(asset)) {
            _swap0(pair, IERC20(pair.token1()).balanceOf(address(this)));
        } else {
            _swap1(pair, IERC20(pair.token0()).balanceOf(address(this)));
        }
        return asset.balanceOf(address(this));
    }

    function _swap0(IPairUniV2 pair, uint256 amt) private returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 iwf = amt * 997;
        uint256 num = iwf * uint256(reserve0);
        uint256 den = (uint256(reserve1) * 1000) + iwf;
        IERC20(pair.token1()).transfer(address(pair), amt);
        pair.swap(num / den, 0, address(this), new bytes(0));
        pair.skim(address(this));
        return num / den;
    }

    function _swap1(IPairUniV2 pair, uint256 amt) private returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 iwf = amt * 997;
        uint256 num = iwf * uint256(reserve1);
        uint256 den = (uint256(reserve0) * 1000) + iwf;
        IERC20(pair.token0()).transfer(address(pair), amt);
        pair.swap(0, num / den, address(this), new bytes(0));
        pair.skim(address(this));
        return num / den;
    }
}

