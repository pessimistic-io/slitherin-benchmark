// SPDX-License-Identifier: Apache-2.0

/*
 * Copyright 2020, Offchain Labs, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

pragma solidity ^0.6.11;

import "./Address.sol";
import "./BytesLib.sol";
import "./ProxyUtil.sol";
import "./AddressAliasHelper.sol";

import "./IArbToken.sol";

import "./L2ArbitrumMessenger.sol";
import "./GatewayMessageHandler.sol";
import "./TokenGateway.sol";

/**
 * @title Common interface for gatways on Arbitrum messaging to L1.
 */
abstract contract L2ArbitrumGateway is L2ArbitrumMessenger, TokenGateway {
    using Address for address;

    uint256 public exitNum;

    event DepositFinalized(address indexed l1Token, address indexed _from, address indexed _to, uint256 _amount);

    event WithdrawalInitiated(address l1Token, address indexed _from, address indexed _to, uint256 indexed _l2ToL1Id, uint256 _exitNum, uint256 _amount);

    modifier onlyCounterpartGateway() override {
        require(msg.sender == counterpartGateway || AddressAliasHelper.undoL1ToL2Alias(msg.sender) == counterpartGateway, "ONLY_COUNTERPART_GATEWAY");
        _;
    }

    function postUpgradeInit() external view {
        // it is assumed the L2 Arbitrum Gateway contract is behind a Proxy controlled by a proxy admin
        // this function can only be called by the proxy admin contract
        address proxyAdmin = ProxyUtil.getProxyAdmin();
        require(msg.sender == proxyAdmin, "NOT_FROM_ADMIN");
        // this has no other logic since the current upgrade doesn't require this logic
    }

    function _initialize(address _l1Counterpart, address _router) internal virtual override {
        TokenGateway._initialize(_l1Counterpart, _router);
        // L1 gateway must have a router
        require(_router != address(0), "BAD_ROUTER");
    }

    function createOutboundTx(
        address,
        uint256, /* _tokenAmount */
        bytes memory
    ) internal pure virtual returns (uint256) {
        return 0;
    }

    function getOutboundCalldata(
        address _token,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _data
    ) public view override returns (bytes memory outboundCalldata) {
        outboundCalldata = abi.encodeWithSelector(
            TokenGateway.finalizeInboundTransfer.selector,
            _token,
            _from,
            _to,
            _amount,
            GatewayMessageHandler.encodeFromL2GatewayMsg(exitNum, _data)
        );

        return outboundCalldata;
    }

    function outboundTransfer(
        address _l1Token,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) public payable virtual returns (bytes memory) {
        return outboundTransfer(_l1Token, _to, _amount, 0, 0, _data);
    }

    function outboundTransfer(
        address,
        address,
        uint256,
        uint256, /* _maxGas */
        uint256, /* _gasPriceBid */
        bytes calldata
    ) public payable virtual override returns (bytes memory res) {
        return abi.encode(0);
    }

    function triggerWithdrawal(
        address,
        address,
        address,
        uint256,
        bytes memory
    ) internal pure returns (uint256) {
        return 0;
    }

    function outboundEscrowTransfer(
        address,
        address,
        uint256
    ) internal pure virtual returns (uint256 amountBurnt) {
        return 0;
    }

    function inboundEscrowTransfer(
        address _l2Address,
        address _dest,
        uint256 _amount,
        bytes memory _data
    ) internal virtual {
        // this method is virtual since different subclasses can handle escrow differently
        IArbToken(_l2Address).bridgeMint(_dest, _amount, _data);
    }

    /**
     * @notice Mint on L2 upon L1 deposit.
     * If token not yet deployed and symbol/name/decimal data is included, deploys StandardArbERC20
     * @dev Callable only by the L1ERC20Gateway.outboundTransfer method. For initial deployments of a token the L1 L1ERC20Gateway
     * is expected to include the deployData. If not a L1 withdrawal is automatically triggered for the user
     * @param _token L1 address of ERC20
     * @param _from account that initiated the deposit in the L1
     * @param _to account to be credited with the tokens in the L2 (can be the user's L2 account or a contract)
     * @param _amount token amount to be minted to the user
     * @param _data encoded symbol/name/decimal data for deploy, in addition to any additional callhook data
     */
    function finalizeInboundTransfer(
        address _token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    ) external payable override onlyCounterpartGateway {
        (, bytes memory callHookData) = GatewayMessageHandler.parseFromL1GatewayMsg(_data);

        address expectedAddress = calculateL2TokenAddress(_token);

        inboundEscrowTransfer(expectedAddress, _to, _amount, callHookData);
        emit DepositFinalized(_token, _from, _to, _amount);

        return;
    }

    // returns if function should halt after
    function handleNoContract(
        address _l1Token,
        address expectedL2Address,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory gatewayData
    ) internal virtual returns (bool shouldHalt);
}

