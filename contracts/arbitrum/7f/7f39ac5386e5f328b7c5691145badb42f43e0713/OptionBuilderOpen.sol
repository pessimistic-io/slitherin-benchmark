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

contract OptionBuilderOpen is BaseOptionBuilder {

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

    // Event emitted when a position is opened using Lyra protocol
    event OpenPositionByLyra(
        uint256 indexed buildID,
        uint256 strikeId,
        uint256 positionId,
        uint256 iterations,
        ILyra.OptionType optionType,
        uint256 amount,
        uint256 setCollateralTo,
        uint256 minTotalCost,
        uint256 maxTotalCost,
        address referrer,
        uint256 tokenID
    );

    // Event emitted when a position is opened using Hegic protocol
    event OpenPositionByHegic(
        uint256 indexed buildID,
        uint256 tokenID,
        address strategy,
        address holder,
        uint256 amount,
        uint256 period,
        uint256 premuim
    );

    function _processLyraProtocol(
        ProtocolType protocolType,
        bytes memory parameters,
        uint256 buildID
    ) override internal {
        (
            ILyra.TradeInputParameters memory params
        ) = decodeFromLyra(parameters);
        
        address lyra = lyra_eth;
        address lyraErc721 = lyra_ethErc721;
        
        // Check the protocol type and set appropriate Lyra and ERC721 token addresses
        if (protocolType == ProtocolType.lyra_btc) {
            lyra = lyra_btc;
            lyraErc721 = lyra_btcErc721;
        }
        
        uint256 premium;
        ERC20 lyraAsset;
        
        // Calculate premium amount and determine Lyra asset based on option type
        if (params.optionType == ILyra.OptionType.LONG_CALL || params.optionType == ILyra.OptionType.LONG_PUT) {
            premium = params.maxTotalCost / (1e18 / 10 ** ILyra(lyra).quoteAsset().decimals());
            lyraAsset = ILyra(lyra).quoteAsset();
        } else if (params.optionType == ILyra.OptionType.SHORT_CALL_QUOTE || params.optionType == ILyra.OptionType.SHORT_PUT_QUOTE) {
            premium = params.setCollateralTo / (1e18 / 10 ** ILyra(lyra).quoteAsset().decimals());
            lyraAsset = ILyra(lyra).quoteAsset();
        } else if (params.optionType == ILyra.OptionType.SHORT_CALL_BASE) {
            premium = params.setCollateralTo / (1e18 / 10 ** ILyra(lyra).baseAsset().decimals());
            lyraAsset = ILyra(lyra).baseAsset();
        }
        
        // Transfer premium amount from sender to the contract
        lyraAsset.transferFrom(msg.sender, address(this), premium);
        
        // Get the next available ERC721 token ID
        uint256 id = IOptionToken(lyraErc721).nextId();
        
        // Open the position using the Lyra contract
        ILyra(lyra).openPosition(params);
        
        // Transfer back remaining tokens to the sender
        lyraAsset.transfer(msg.sender, lyraAsset.balanceOf(address(this)));
        
        // Transfer ERC721 token representing the option to the sender
        IOptionToken(lyraErc721).transferFrom(address(this), msg.sender, id);
        if (params.optionType == ILyra.OptionType.SHORT_CALL_BASE) {
            ILyra(lyra).quoteAsset().transfer(msg.sender, ILyra(lyra).quoteAsset().balanceOf(address(this)));
        }
        
        // Emit the OpenPositionByLyra event with relevant parameters
        emit OpenPositionByLyra(
            buildID,
            params.strikeId,
            params.positionId,
            params.iterations,
            params.optionType,
            params.amount,
            params.setCollateralTo,
            params.minTotalCost,
            params.maxTotalCost,
            params.referrer,
            id
        );
    }

    function _processHegicProtocol(bytes memory parameters, uint256 buildID) internal override {
        (
            IHegicStrategy strategy,
            address holder,
            uint256 amount,
            uint256 period,
            bytes[] memory additional
        ) = decodeFromHegic(parameters);
        
        // Calculate the premium amount from positive pnl using the Hegic strategy
        (, uint128 positivepnl) = strategy.calculateNegativepnlAndPositivepnl(amount, period, additional);
        uint256 premium = uint256(positivepnl);
        
        // Transfer premium amount in USDC from sender to the contract
        ERC20(usdc).transferFrom(msg.sender, address(this), premium);
        
        // Get the next available ERC721 token ID
        uint256 id = IPositionsManager(hegicErc721).nextTokenId();
        
        // Buy the option using the operational treasury contract
        IOperationalTreasury(operationalTreasury).buy(
            strategy,
            holder,
            amount,
            period,
            additional
        );
        
        // Transfer ERC721 token representing the option to the sender
        IPositionsManager(hegicErc721).transferFrom(address(this), msg.sender, id);
        
        // Emit the OpenPositionByHegic event with relevant parameters
        emit OpenPositionByHegic(buildID, id, address(strategy), holder, amount, period, premium);
    }

    // Encode TradeInputParameters struct into bytes
    function encodeFromLyra(ILyra.TradeInputParameters memory params) external pure returns (bytes memory paramData) {
        return abi.encode(params);
    }

    function decodeFromLyra(bytes memory paramData) public pure returns (ILyra.TradeInputParameters memory params) {
        (
            params
        ) = abi.decode(paramData, (
            ILyra.TradeInputParameters
        ));
    }


    // Encode Hegic parameters into bytes
    function encodeFromHegic(
        IHegicStrategy strategy,
        address holder,
        uint256 amount,
        uint256 period,
        bytes[] memory additional
    ) external pure returns (bytes memory paramData) {
        return abi.encode(strategy, holder, amount, period, additional);
    }

    function decodeFromHegic(
        bytes memory paramData
    ) public pure returns (
        IHegicStrategy strategy,
        address holder,
        uint256 amount,
        uint256 period,
        bytes[] memory additional
    ) {
        (
            strategy,
            holder,
            amount,
            period,
            additional
        ) = abi.decode(paramData, (
            IHegicStrategy,
            address,
            uint256,
            uint256,
            bytes[]
        ));
    }
}

