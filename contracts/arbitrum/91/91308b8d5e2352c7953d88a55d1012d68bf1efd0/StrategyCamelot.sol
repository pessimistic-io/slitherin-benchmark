// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IERC20} from "./IERC20.sol";
import {IPairUniV2} from "./IPairUniV2.sol";
import {Strategy} from "./Strategy.sol";

interface ICamelotNFTPoolFactory {
    function grailToken() external view returns (address);
    function xGrailToken() external view returns (address);
    function getPool(address lp) external view returns (address nftPool);
}

interface ICamelotNFTPool {
    function lastTokenId() external view returns (uint256);
    function getStakingPosition(uint256 id) external view returns (uint256);
    function createPosition(uint256 amt, uint256 lok) external;
    function addToPosition(uint256 id, uint256 amt) external;
    function harvestPosition(uint256 id) external;
    function withdrawFromPosition(uint256 id, uint256 amt) external;
    function transferFrom(address from, address to, uint256 id) external;
}

contract StrategyCamelot is Strategy {
    string public name;
    ICamelotNFTPool public nftPool;
    IPairUniV2 public pool;
    IERC20 public grail;
    IERC20 public xGrail;
    uint256 public tokenId;

    constructor(address _strategyHelper, address _nftPoolFactory, address _pool) Strategy(_strategyHelper) {
        ICamelotNFTPoolFactory factory = ICamelotNFTPoolFactory(_nftPoolFactory);
        grail = IERC20(factory.grailToken());
        xGrail = IERC20(factory.xGrailToken());
        nftPool = ICamelotNFTPool(factory.getPool(_pool));
        pool = IPairUniV2(_pool);
        name = string(abi.encodePacked("Camelot ", IERC20(pool.token0()).symbol(), "/", IERC20(pool.token1()).symbol()));
    }

    function _rate(uint256 sha) internal view override returns (uint256) {
        IPairUniV2 pair = pool;
        uint256 tot = pair.totalSupply();
        uint256 amt = totalManagedAssets();
        uint256 reserve0;
        uint256 reserve1;
        {
            (uint112 r0, uint112 r1,) = pair.getReserves();
            reserve0 = uint256(r0) * 1e18 / (10 ** IERC20(pair.token0()).decimals());
            reserve1 = uint256(r1) * 1e18 / (10 ** IERC20(pair.token1()).decimals());
        }
        uint256 price0 = strategyHelper.price(pair.token0());
        uint256 price1 = strategyHelper.price(pair.token1());
        uint256 val = 2 * ((sqrt(reserve0 * reserve1) * sqrt(price0 * price1)) / tot);
        return sha * (val * amt / 1e18) / totalShares;
    }

    function _mint(address ast, uint256 amt, bytes calldata dat) internal override returns (uint256) {
        earn();
        pull(IERC20(ast), msg.sender, amt);
        uint256 slp = getSlippage(dat);
        uint256 tma = totalManagedAssets();
        uint256 liq = _mintAndStake(ast, slp);
        return tma == 0 ? liq : liq * totalShares / tma;
    }

    function _burn(address ast, uint256 sha, bytes calldata dat) internal override returns (uint256) {
        earn();
        IPairUniV2 pair = pool;
        uint256 slp = getSlippage(dat);
        {
            uint256 tma = totalManagedAssets();
            uint256 amt = sha * tma / totalShares;
            _unstake(amt);
            IERC20(address(pair)).transfer(address(pair), amt);
            pair.burn(address(this));
        }
        IERC20 tok0 = IERC20(pair.token0());
        IERC20 tok1 = IERC20(pair.token1());
        uint256 bal0 = tok0.balanceOf(address(this));
        uint256 bal1 = tok1.balanceOf(address(this));
        tok0.approve(address(strategyHelper), bal0);
        tok1.approve(address(strategyHelper), bal1);
        uint256 amt0 = strategyHelper.swap(address(tok0), ast, bal0, slp, msg.sender);
        uint256 amt1 = strategyHelper.swap(address(tok1), ast, bal1, slp, msg.sender);
        return amt0 + amt1;
    }

    function _earn() internal override {
        IPairUniV2 pair = pool;
        nftPool.harvestPosition(tokenId);
        if (strategyHelper.value(address(grail), grail.balanceOf(address(this))) < 0.5e18) return;
        _mintAndStake(address(grail), slippage);
    }

    function totalManagedAssets() public view returns (uint256) {
        return nftPool.getStakingPosition(tokenId);
    }

    function _mintAndStake(address ast, uint256 slp) internal returns (uint256) {
        IPairUniV2 pair = pool;
        IERC20 tok0 = IERC20(pair.token0());
        IERC20 tok1 = IERC20(pair.token1());
        uint256 amt = IERC20(ast).balanceOf(address(this));
        uint256 haf = amt / 2;
        IERC20(ast).approve(address(strategyHelper), amt);
        strategyHelper.swap(ast, address(tok0), haf, slp, address(this));
        strategyHelper.swap(ast, address(tok1), amt-haf, slp, address(this));
        push(tok0, address(pair), tok0.balanceOf(address(this)));
        push(tok1, address(pair), tok1.balanceOf(address(this)));
        pair.mint(address(this));
        pair.skim(address(this));
        return _stake();
    }

    function _stake() internal returns (uint256) {
        uint256 liq = IERC20(address(pool)).balanceOf(address(this));
        IERC20(address(pool)).approve(address(nftPool), liq);
        if (tokenId > 0) {
            nftPool.addToPosition(tokenId, liq);
        } else {
            nftPool.createPosition(liq, 0);
            tokenId = nftPool.lastTokenId();
        }
        return liq;
    }

    function _unstake(uint256 amt) internal {
        nftPool.withdrawFromPosition(tokenId, amt);
    }

    function _exit(address str) internal override {
        nftPool.transferFrom(address(this), str, tokenId);
    }

    function _move(address old) internal override {
        tokenId = StrategyCamelot(old).tokenId();
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return StrategyCamelot.onERC721Received.selector;
    }

    function onNFTHarvest(address, address, uint256, uint256, uint256) public returns (bool) {
        return true;
    }
    function onNFTAddToPosition(address, uint256, uint256) public returns (bool) {
        return true;
    }
    function onNFTWithdraw(address, uint256, uint256) public returns (bool) {
        return true;
    }
}

