// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.0;

import "./IHopL1Bridge.sol";
import "./FixedPoint.sol";
import "./EnumerableMap.sol";

import "./BaseHopBridger.sol";

contract L1HopBridger is BaseHopBridger {
    using FixedPoint for uint256;
    using EnumerableMap for EnumerableMap.AddressToAddressMap;

    // Base gas amount charged to cover gas payment
    uint256 public constant override BASE_GAS = 120e3;

    mapping (address => uint256) public getMaxRelayerFeePct;
    EnumerableMap.AddressToAddressMap private tokenBridges;

    event TokenBridgeSet(address indexed token, address indexed bridge);
    event MaxRelayerFeePctSet(address indexed relayer, uint256 maxFeePct);

    constructor(address admin, address registry) BaseAction(admin, registry) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getTokensLength() external view override returns (uint256) {
        return tokenBridges.length();
    }

    function getTokenBridge(address token) external view returns (address bridge) {
        (, bridge) = tokenBridges.tryGet(token);
    }

    function getTokens() external view override returns (address[] memory tokens) {
        tokens = new address[](tokenBridges.length());
        for (uint256 i = 0; i < tokens.length; i++) {
            (address token, ) = tokenBridges.at(i);
            tokens[i] = token;
        }
    }

    function getTokenBridges() external view returns (address[] memory tokens, address[] memory bridges) {
        tokens = new address[](tokenBridges.length());
        bridges = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            (address token, address bridge) = tokenBridges.at(i);
            tokens[i] = token;
            bridges[i] = bridge;
        }
    }

    function setMaxRelayerFeePct(address relayer, uint256 newMaxFeePct) external auth {
        require(newMaxFeePct <= FixedPoint.ONE, 'BRIDGER_RELAYER_FEE_PCT_GT_ONE');
        getMaxRelayerFeePct[relayer] = newMaxFeePct;
        emit MaxRelayerFeePctSet(relayer, newMaxFeePct);
    }

    function setTokenBridge(address token, address bridge) external auth {
        require(token != address(0), 'BRIDGER_TOKEN_ZERO');
        require(!Denominations.isNativeToken(token), 'BRIDGER_NATIVE_TOKEN');
        bridge == address(0) ? tokenBridges.remove(token) : tokenBridges.set(token, bridge);
        emit TokenBridgeSet(token, bridge);
    }

    function call(address token, uint256 slippage, address relayer, uint256 relayerFee) external auth nonReentrant {
        _initRelayedTx();
        uint256 balance = _balanceOf(token);
        bytes memory data = _prepareBridge(token, balance, slippage, relayer, relayerFee);
        uint256 gasRefund = _payRelayedTx(token);
        _bridge(token, balance - gasRefund, slippage, data);
    }

    function _prepareBridge(address token, uint256 amount, uint256 slippage, address relayer, uint256 relayerFee)
        internal
        returns (bytes memory)
    {
        (bool existsBridge, address bridge) = tokenBridges.tryGet(token);
        require(existsBridge, 'BRIDGER_TOKEN_BRIDGE_NOT_SET');
        require(amount > 0, 'BRIDGER_AMOUNT_ZERO');
        require(destinationChainId != 0, 'BRIDGER_CHAIN_NOT_SET');
        require(slippage <= maxSlippage, 'BRIDGER_SLIPPAGE_ABOVE_MAX');
        require(relayerFee.divUp(amount) <= getMaxRelayerFeePct[relayer], 'BRIDGER_RELAYER_FEE_ABOVE_MAX');
        _validateThreshold(token, amount);

        uint256 deadline = block.timestamp + maxDeadline;
        bytes memory data = abi.encode(bridge, deadline, relayer, relayerFee);

        emit Executed();
        return data;
    }
}

