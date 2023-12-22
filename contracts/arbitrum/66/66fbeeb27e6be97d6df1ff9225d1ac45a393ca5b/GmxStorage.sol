// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {IGmxPositionRouter} from "./IGmxPositionRouter.sol";

contract GmxStorage {
    struct Gmx {
        address vault;
        address router;
        address positionRouter;
        address orderBook;
        address reader;
        address defaultShortCollateral;
    }

    // struct which contains all the necessary contract addresses of GMX
    // check `IReaderStorage.Gmx`
    Gmx public dex;

    function getGmxVault() internal view returns (address) {
        return dex.vault;
    }

    function getGmxRouter() internal view returns (address) {
        return dex.router;
    }

    function getGmxPositionRouter() internal view returns (address) {
        return dex.positionRouter;
    }

    function getGmxOrderBook() internal view returns (address) {
        return dex.orderBook;
    }

    function getGmxReader() internal view returns (address) {
        return dex.reader;
    }

    function getGmxDefaultShortCollateral() internal view returns (address) {
        return dex.defaultShortCollateral;
    }

    function getGmxFee() internal view returns (uint256 fee) {
        address _gmxPositionRouter = getGmxPositionRouter();
        /// GMX checks if `msg.value >= fee` for closing positions, so we need 1 more WEI to pass.
        fee = IGmxPositionRouter(_gmxPositionRouter).minExecutionFee();
    }

    function getPath(bool _isClose, bool _tradeDirection, address _depositToken, address _tradeToken)
        internal
        view
        returns (address[] memory _path)
    {
        if (_isClose) {
            if (_tradeDirection) {
                // for long, the collateral is in the tradeToken,
                // we swap from tradeToken to usdc, path[0] = tradeToken
                _path = new address[](2);
                _path[0] = _tradeToken;
                _path[1] = dex.defaultShortCollateral;
            } else {
                // for short, the collateral is in stable coin,
                // so the path only needs depositToken since there's no swap
                _path = new address[](1);
                _path[0] = _depositToken;
            }
        } else {
            if (_tradeDirection) {
                // for long, the collateral is in the tradeToken,
                //  we swap from usdc to tradeToken, path[0] = depositToken
                _path = new address[](2);
                _path[0] = _depositToken;
                _path[1] = _tradeToken;
            } else {
                // for short, the collateral is in stable coin,
                // so the path only needs depositToken since there's no swap
                _path = new address[](1);
                _path[0] = _depositToken;
            }
        }
    }
}

