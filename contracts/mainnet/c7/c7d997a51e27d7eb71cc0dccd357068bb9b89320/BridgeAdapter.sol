// SPDX-License-Identifier: Apache-2.0
/*

  Copyright 2021 ZeroEx Intl.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/

pragma solidity ^0.6.5;
pragma experimental ABIEncoderV2;

import "./IBridgeAdapter.sol";
import "./BridgeProtocols.sol";
import "./MixinBalancer.sol";
import "./MixinBancor.sol";
import "./MixinCoFiX.sol";
import "./MixinCurve.sol";
import "./MixinCryptoCom.sol";
import "./MixinDodo.sol";
import "./MixinDodoV2.sol";
import "./MixinKyber.sol";
import "./MixinMakerPSM.sol";
import "./MixinMooniswap.sol";
import "./MixinMStable.sol";
import "./MixinNerve.sol";
import "./MixinOasis.sol";
import "./MixinShell.sol";
import "./MixinUniswap.sol";
import "./MixinUniswapV2.sol";
import "./MixinZeroExBridge.sol";

contract BridgeAdapter is
    IBridgeAdapter,
    MixinBalancer,
    MixinBancor,
    MixinCoFiX,
    MixinCurve,
    MixinCryptoCom,
    MixinDodo,
    MixinDodoV2,
    MixinKyber,
    MixinMakerPSM,
    MixinMooniswap,
    MixinMStable,
    MixinNerve,
    MixinOasis,
    MixinShell,
    MixinUniswap,
    MixinUniswapV2,
    MixinZeroExBridge
{
    constructor(IEtherTokenV06 weth)
        public
        MixinBalancer()
        MixinBancor(weth)
        MixinCoFiX()
        MixinCurve()
        MixinCryptoCom()
        MixinDodo()
        MixinDodoV2()
        MixinKyber(weth)
        MixinMakerPSM()
        MixinMooniswap(weth)
        MixinMStable()
        MixinNerve()
        MixinOasis()
        MixinShell()
        MixinUniswap(weth)
        MixinUniswapV2()
        MixinZeroExBridge()
    {}

    function trade(
        BridgeOrder memory order,
        IERC20TokenV06 sellToken,
        IERC20TokenV06 buyToken,
        uint256 sellAmount
    )
        public
        override
        returns (uint256 boughtAmount)
    {
        uint128 protocolId = uint128(uint256(order.source) >> 128);
        if (protocolId == BridgeProtocols.CURVE) {
            boughtAmount = _tradeCurve(
                sellToken,
                buyToken,
                sellAmount,
                order.bridgeData
            );
        } else if (protocolId == BridgeProtocols.UNISWAPV2) {
            boughtAmount = _tradeUniswapV2(
                buyToken,
                sellAmount,
                order.bridgeData
            );
        } else if (protocolId == BridgeProtocols.UNISWAP) {
            boughtAmount = _tradeUniswap(
                sellToken,
                buyToken,
                sellAmount,
                order.bridgeData
            );
        } else if (protocolId == BridgeProtocols.BALANCER) {
            boughtAmount = _tradeBalancer(
                sellToken,
                buyToken,
                sellAmount,
                order.bridgeData
            );
        } else if (protocolId == BridgeProtocols.KYBER) {
            boughtAmount = _tradeKyber(
                sellToken,
                buyToken,
                sellAmount,
                order.bridgeData
            );
        } else if (protocolId == BridgeProtocols.MAKERPSM) {
            boughtAmount = _tradeMakerPsm(
                sellToken,
                buyToken,
                sellAmount,
                order.bridgeData
            );
        } else if (protocolId == BridgeProtocols.MOONISWAP) {
            boughtAmount = _tradeMooniswap(
                sellToken,
                buyToken,
                sellAmount,
                order.bridgeData
            );
        } else if (protocolId == BridgeProtocols.MSTABLE) {
            boughtAmount = _tradeMStable(
                sellToken,
                buyToken,
                sellAmount,
                order.bridgeData
            );
        } else if (protocolId == BridgeProtocols.OASIS) {
            boughtAmount = _tradeOasis(
                sellToken,
                buyToken,
                sellAmount,
                order.bridgeData
            );
        } else if (protocolId == BridgeProtocols.SHELL) {
            boughtAmount = _tradeShell(
                sellToken,
                buyToken,
                sellAmount,
                order.bridgeData
            );
        } else if (protocolId == BridgeProtocols.DODO) {
            boughtAmount = _tradeDodo(
                sellToken,
                sellAmount,
                order.bridgeData
            );
        } else if (protocolId == BridgeProtocols.DODOV2) {
            boughtAmount = _tradeDodoV2(
                sellToken,
                sellAmount,
                order.bridgeData
            );
        } else if (protocolId == BridgeProtocols.CRYPTOCOM) {
            boughtAmount = _tradeCryptoCom(
                buyToken,
                sellAmount,
                order.bridgeData
            );
        } else if (protocolId == BridgeProtocols.BANCOR) {
            boughtAmount = _tradeBancor(
                buyToken,
                sellAmount,
                order.bridgeData
            );
        } else if (protocolId == BridgeProtocols.COFIX) {
            boughtAmount = _tradeCoFiX(
                sellToken,
                buyToken,
                sellAmount,
                order.bridgeData
            );
        } else if (protocolId == BridgeProtocols.NERVE) {
            boughtAmount = _tradeNerve(
                sellToken,
                sellAmount,
                order.bridgeData
            );
        } else {
            boughtAmount = _tradeZeroExBridge(
                sellToken,
                buyToken,
                sellAmount,
                order.bridgeData
            );
        }

        emit BridgeFill(
            order.source,
            sellToken,
            buyToken,
            sellAmount,
            boughtAmount
        );
    }
}

