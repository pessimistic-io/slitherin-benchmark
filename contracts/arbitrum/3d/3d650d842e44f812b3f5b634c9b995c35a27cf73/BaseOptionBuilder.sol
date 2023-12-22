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

import "./IERC721.sol";
import "./ERC20.sol";
import "./Ownable.sol";
import "./IHegicStrategy.sol";

interface ILyra {
    enum OptionType {
        LONG_CALL,
        LONG_PUT,
        SHORT_CALL_BASE,
        SHORT_CALL_QUOTE,
        SHORT_PUT_QUOTE
    }

    struct Result {
        uint positionId;
        uint totalCost;
        uint totalFee;
    }

    struct TradeInputParameters {
        // id of strike
        uint strikeId;
        // OptionToken ERC721 id for position (set to 0 for new positions)
        uint positionId;
        // number of sub-orders to break order into (reduces slippage)
        uint iterations;
        // type of option to trade
        OptionType optionType;
        // number of contracts to trade
        uint amount;
        // final amount of collateral to leave in OptionToken position
        uint setCollateralTo;
        // revert trade if totalCost is below this value
        uint minTotalCost;
        // revert trade if totalCost is above this value
        uint maxTotalCost;
        // referrer emitted in Trade event, no on-chain interaction
        address referrer;
    }

    function openPosition(TradeInputParameters memory params) external returns (Result memory result);
    function closePosition(TradeInputParameters memory params) external returns (Result memory result);
    function quoteAsset() external view returns(ERC20);
    function baseAsset() external view returns(ERC20);
}

interface IOptionToken is IERC721 {
    function nextId() external view returns (uint256);
}

interface IOperationalTreasury {
    function buy(
        IHegicStrategy strategy,
        address holder,
        uint256 amount,
        uint256 period,
        bytes[] calldata additional
    ) external;

    function payOff(uint256 positionID, address account) external;
}

interface IPositionsManager is IERC721 {
    function nextTokenId() external view returns (uint256);
}

abstract contract BaseOptionBuilder is Ownable{
    
    // Enumeration of different protocol types
    enum ProtocolType {
        lyra_eth,
        lyra_btc,
        hegic
    }

    // State variables
    address public lyra_eth; // Address of Lyra ETH contract
    address public lyra_btc; // Address of Lyra BTC contract
    address public operationalTreasury; // Address of operational treasury

    address public lyra_ethErc721; // Address of Lyra ETH ERC721 token contract
    address public lyra_btcErc721; // Address of Lyra BTC ERC721 token contract
    address public hegicErc721; // Address of Hegic ERC721 token contract

    address public usdc; // Address of USDC ERC20 token contract

    uint256 public nextBuildID = 1;

    // Constructor
    constructor (
        address _lyra_eth,
        address _lyra_btc,
        address _operationalTreasury,
        address _lyra_ethErc721,
        address _lyra_btcErc721,
        address _hegicErc721,
        address _usdc
    ) {
        lyra_eth = _lyra_eth;
        lyra_btc = _lyra_btc;
        operationalTreasury = _operationalTreasury;
        lyra_ethErc721 = _lyra_ethErc721;
        lyra_btcErc721 = _lyra_btcErc721;
        hegicErc721 = _hegicErc721;
        usdc = _usdc;
    }

    event CreateBuild(
        uint256 buildID,
        address indexed user,
        uint256 productType
    );

    // Approve maximum spending limits for tokens used in the contract
    function allApprove() external {
        ILyra(lyra_eth).quoteAsset().approve(lyra_eth, type(uint256).max);
        ILyra(lyra_eth).baseAsset().approve(lyra_eth, type(uint256).max);
        ILyra(lyra_btc).quoteAsset().approve(lyra_btc, type(uint256).max);
        ILyra(lyra_btc).baseAsset().approve(lyra_btc, type(uint256).max);
        ERC20(usdc).approve(operationalTreasury, type(uint256).max);
    }

    // Process a transaction using Lyra protocol
    function _processLyraProtocol(
        ProtocolType protocolType,
        bytes memory parametersArray,
        uint256 buildID
    ) internal virtual {}

    // Process a transaction using Hegic protocol
    function _processHegicProtocol(bytes memory parametersArray, uint256 buildID) internal virtual {}

    // Consolidate multiple transactions into a single function call
    function consolidationOfTransactions(ProtocolType[] memory protocolsArrays, bytes[] memory parametersArray, uint256 productType) external {
        require(protocolsArrays.length == parametersArray.length, "arrays not equal");
        
        for (uint i = 0; i < protocolsArrays.length; i++) {
            if (protocolsArrays[i] == ProtocolType.lyra_eth || protocolsArrays[i] == ProtocolType.lyra_btc) {
                _processLyraProtocol(protocolsArrays[i], parametersArray[i], nextBuildID);
            } else if (protocolsArrays[i] == ProtocolType.hegic) {
                _processHegicProtocol(parametersArray[i], nextBuildID);
            }
        }

        emit CreateBuild(nextBuildID, msg.sender, productType);
        nextBuildID++;
    }

    function onERC721Received(
        address, 
        address, 
        uint256, 
        bytes calldata
    )external returns(bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    } 
}

