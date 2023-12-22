/**
 * SPDX-License-Identifier: GPL-3.0-or-later
 * DeDeLend
 * Copyright (C) 2023 DeDeLend
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 **/

pragma solidity 0.8.9;

import "./BaseOptionBuilder.sol";

contract OptionBuilderClose is BaseOptionBuilder {

    // Constructor
    constructor(
        address _lyra_eth,
        address _lyra_btc,
        address _operationalTreasury,
        address _lyra_ethErc721,
        address _lyra_btcErc721,
        address _hegicErc721,
        address _usdc
    ) BaseOptionBuilder(
        _lyra_eth,
        _lyra_btc,
        _operationalTreasury,
        _lyra_ethErc721,
        _lyra_btcErc721,
        _hegicErc721,
        _usdc
    ) {}

    // Event emitted when a position is closed using Lyra protocol
    event ClosePositionByLyra(
        uint256 indexed buildID,
        uint256 strikeId,
        uint256 positionId,
        uint256 iterations,
        ILyra.OptionType optionType,
        uint256 amount,
        uint256 setCollateralTo,
        uint256 minTotalCost,
        uint256 maxTotalCost,
        address referrer
    );

    // Event emitted when a position is closed using Hegic protocol
    event ClosePositionByHegic(
        uint256 indexed buildID,
        uint256 tokenID,
        address account
    );

    function _processLyraProtocol(
        ProtocolType protocolType,
        bytes memory parameters,
        uint256 buildID
    ) override internal {
        (
            address account,
            ILyra.TradeInputParameters memory params, 
            uint256 premium
        ) = decodeFromLyra(parameters);
        
        address lyra = lyra_eth;
        address lyraErc721 = lyra_ethErc721;
        
        // Check the protocol type and set appropriate Lyra and ERC721 token addresses
        if (protocolType == ProtocolType.lyra_btc) {
            lyra = lyra_btc;
            lyraErc721 = lyra_btcErc721;
        }
        
        // Calculate determine Lyra asset based on option type
        ERC20 lyraAsset = params.optionType == ILyra.OptionType.SHORT_CALL_BASE ? ILyra(lyra).baseAsset() : ILyra(lyra).quoteAsset();

        // Transfer premium amount from sender to the contract
        ILyra(lyra).quoteAsset().transferFrom(msg.sender, address(this), premium);
        
        IOptionToken(lyraErc721).transferFrom(account, address(this), params.positionId);
        
        // Close the position using the Lyra contract
        ILyra(lyra).closePosition(params);
        
        // Transfer back remaining tokens to the sender
        lyraAsset.transfer(account, lyraAsset.balanceOf(address(this)));
        if (params.optionType == ILyra.OptionType.SHORT_CALL_BASE) {
            ILyra(lyra).quoteAsset().transfer(account, ILyra(lyra).quoteAsset().balanceOf(address(this)));
        }
        
        // Emit the ClosePositionByLyra event with relevant parameters
        emit ClosePositionByLyra(
            buildID,
            params.strikeId,
            params.positionId,
            params.iterations,
            params.optionType,
            params.amount,
            params.setCollateralTo,
            params.minTotalCost,
            params.maxTotalCost,
            params.referrer
        );
    }

    function _processHegicProtocol(bytes memory parameters, uint256 buildID) internal override {
        (
            address account,
            uint256 positionID
        ) = decodeFromHegic(parameters);
        
        IPositionsManager(hegicErc721).transferFrom(account, address(this), positionID);
        
        // Buy the option using the operational treasury contract
        IOperationalTreasury(operationalTreasury).payOff(
            positionID,
            account
        );
        
        // Emit the ClosePositionByHegic event with relevant parameters
        emit ClosePositionByHegic(buildID, positionID, account);
    }

    // Encode TradeInputParameters struct into bytes
    function encodeFromLyra(address account, ILyra.TradeInputParameters memory params, uint256 premium) external pure returns (bytes memory paramData) {
        return abi.encode(account, params, premium);
    }

    function decodeFromLyra(bytes memory paramData) public pure returns (address account, ILyra.TradeInputParameters memory params, uint256 premium) {
        (
            account,
            params,
            premium
        ) = abi.decode(paramData, (
            address,
            ILyra.TradeInputParameters,
            uint256
        ));
    }

    // Encode Hegic parameters into bytes
    function encodeFromHegic(
        address account,
        uint256 positionID
    ) external pure returns (bytes memory paramData) {
        return abi.encode(account, positionID);
    }

    function decodeFromHegic(
        bytes memory paramData
    ) public pure returns (address account, uint256 positionID) {
        (
            account,
            positionID
        ) = abi.decode(paramData, (
            address,
            uint256
        ));
    }
}

