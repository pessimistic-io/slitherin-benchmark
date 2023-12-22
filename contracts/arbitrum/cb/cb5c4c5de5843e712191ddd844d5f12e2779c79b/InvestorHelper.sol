// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IERC20} from "./IERC20.sol";
import {IPool} from "./IPool.sol";
import {IOracle} from "./IOracle.sol";
import {IInvestor} from "./IInvestor.sol";
import {IStrategy} from "./IStrategy.sol";
import {IRateModel} from "./IRateModel.sol";

contract InvestorHelper {
    error TransferFailed();

    uint256 private constant ONE_YEAR = 31536000;
    IInvestor public immutable i;

    constructor(address _i) {
        i = IInvestor(_i);
    }

    function aggregate(address[] memory targets, bytes[] memory data)
        public
        returns (uint256, bytes[] memory)
    {
        bytes[] memory returnData = new bytes[](targets.length);
        for (uint256 j = 0; j < targets.length; j++) {
            (bool success, bytes memory ret) =
                targets[j].call(data[j]);
            require(success);
            returnData[j] = ret;
        }
        return (block.number, returnData);
    }

    function peekPoolInfos(address[] calldata pools)
        external
        view
        returns (address[] memory, bool[] memory, uint256[] memory, uint256[] memory, uint256[] memory, uint256[] memory)
    {
        address[] memory asset = new address[](pools.length);
        bool[] memory paused = new bool[](pools.length);
        uint256[] memory borrowMin = new uint256[](pools.length);
        uint256[] memory borrowFactor = new uint256[](pools.length);
        uint256[] memory liquidationFactor = new uint256[](pools.length);
        uint256[] memory amountCap = new uint256[](pools.length);
        for (uint256 j = 0; j < pools.length; j++) {
            IPool pool = IPool(pools[j]);
            asset[j] = pool.asset();
            paused[j] = pool.paused();
            borrowMin[j] = pool.borrowMin();
            borrowFactor[j] = pool.borrowFactor();
            liquidationFactor[j] = pool.liquidationFactor();
            amountCap[j] = pool.amountCap();
        }
        return (asset, paused, borrowMin, borrowFactor, liquidationFactor, amountCap);
    }

    function peekPools(address[] calldata pools)
        external
        view
        returns (uint256[] memory, uint256[] memory, uint256[] memory, uint256[] memory, uint256[] memory, uint256[] memory)
    {
        uint256[] memory index = new uint256[](pools.length);
        uint256[] memory share = new uint256[](pools.length);
        uint256[] memory supply = new uint256[](pools.length);
        uint256[] memory borrow = new uint256[](pools.length);
        uint256[] memory rate = new uint256[](pools.length);
        uint256[] memory price = new uint256[](pools.length);
        for (uint256 j = 0; j < pools.length; j++) {
            IPool pool = IPool(pools[j]);
            index[j] = pool.getUpdatedIndex();
            share[j] = pool.totalSupply();
            borrow[j] = pool.totalBorrow() * index[j] / 1e18;
            supply[j] = borrow[j] + IERC20(pool.asset()).balanceOf(address(pool));
            if (supply[j] > 0) rate[j] = IRateModel(pool.rateModel()).rate(borrow[j] * 1e18 / supply[j]);
            IOracle oracle = IOracle(pool.oracle());
            price[j] = uint256(oracle.latestAnswer()) * 1e18 / (10 ** oracle.decimals());
        }
        return (index, share, supply, borrow, rate, price);
    }

    function peekPosition(uint256 id)
        external
        view
        returns (
            address pool,
            address strategy,
            uint256 sha,
            uint256 bor,
            uint256 shaval,
            uint256 borval,
            uint256 lif,
            uint256 amt,
            uint256 price
        )
    {
        (, pool, strategy, amt, sha, bor) = i.positions(id);
        lif = i.life(id);
        shaval = IStrategy(strategy).rate(sha);
        borval = bor * IPool(pool).getUpdatedIndex() / 1e18;
        IOracle o = IOracle(IPool(pool).oracle());
        price = uint256(o.latestAnswer()) * 1e18 / (10 ** o.decimals());
    }

    function lifeBatched(uint256[] calldata positionIds) external view returns (uint256[] memory) {
        uint256 posLen = positionIds.length;
        uint256[] memory lifeArr = new uint256[](posLen);
        for (uint256 j = 0; j < posLen; j++) {
            (,,,,, uint256 borrow) = i.positions(positionIds[j]);
            if (borrow == 0) {
                lifeArr[j] = 0;
            } else {
                lifeArr[j] = i.life(positionIds[j]);
            }
        }
        return lifeArr;
    }

    function killBatched(uint256[] calldata ids, bytes[] calldata dat, address usr) external {
        for (uint256 j = 0; j < ids.length; j++) {
            (,address pol,,,,) = i.positions(ids[j]);
            address ast = IPool(pol).asset();
            address(i).call(abi.encodeWithSelector(IInvestor.kill.selector, ids[j], dat[j]));
            uint256 bal = IERC20(ast).balanceOf(address(this));
            if (bal > 0) push(ast, usr, bal);
        }
    }

    function push(address ast, address usr, uint256 amt) internal {
        if (!IERC20(ast).transfer(usr, amt)) revert TransferFailed();
    }
}

