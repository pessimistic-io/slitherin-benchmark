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

import "./Strings.sol";
import "./IERC20Metadata.sol";

import "./ERC20Helpers.sol";

import "./IAxelarGateway.sol";

/**
 * @title AxelarConnector
 * @dev Interfaces with Axelar to bridge tokens
 */
contract AxelarConnector {
    // List of chain names supported by Axelar
    string private constant ETHEREUM_NAME = 'Ethereum';
    string private constant POLYGON_NAME = 'Polygon';
    string private constant ARBITRUM_NAME = 'arbitrum';
    string private constant BSC_NAME = 'binance';
    string private constant FANTOM_NAME = 'Fantom';
    string private constant AVALANCHE_NAME = 'Avalanche';

    // List of chain IDs supported by Axelar
    uint256 private constant ETHEREUM_ID = 1;
    uint256 private constant POLYGON_ID = 137;
    uint256 private constant ARBITRUM_ID = 42161;
    uint256 private constant BSC_ID = 56;
    uint256 private constant FANTOM_ID = 250;
    uint256 private constant AVALANCHE_ID = 43114;

    // Reference to the Axelar gateway of the source chain
    IAxelarGateway public immutable axelarGateway;

    /**
     * @dev Creates a new Axelar connector
     * @param _axelarGateway Address of the Axelar gateway for the source chain
     */
    constructor(address _axelarGateway) {
        axelarGateway = IAxelarGateway(_axelarGateway);
    }

    /**
     * @dev Executes a bridge of assets using Axelar
     * @param chainId ID of the destination chain
     * @param token Address of the token to be bridged
     * @param amountIn Amount of tokens to be bridged
     * @param recipient Address that will receive the tokens on the destination chain
     */
    function execute(uint256 chainId, address token, uint256 amountIn, address recipient) external {
        require(block.chainid != chainId, 'AXELAR_BRIDGE_SAME_CHAIN');
        require(recipient != address(0), 'AXELAR_BRIDGE_RECIPIENT_ZERO');

        string memory chainName = _getChainName(chainId);
        string memory symbol = IERC20Metadata(token).symbol();

        uint256 preBalanceIn = IERC20(token).balanceOf(address(this));

        ERC20Helpers.approve(token, address(axelarGateway), amountIn);
        axelarGateway.sendToken(chainName, Strings.toHexString(recipient), symbol, amountIn);

        uint256 postBalanceIn = IERC20(token).balanceOf(address(this));
        require(postBalanceIn >= preBalanceIn - amountIn, 'AXELAR_BAD_TOKEN_IN_BALANCE');
    }

    /**
     * @dev Tells the chain name based on a chain ID
     * @param chainId ID of the chain being queried
     * @return Chain name associated to the requested chain ID
     */
    function _getChainName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == ETHEREUM_ID) return ETHEREUM_NAME;
        else if (chainId == POLYGON_ID) return POLYGON_NAME;
        else if (chainId == ARBITRUM_ID) return ARBITRUM_NAME;
        else if (chainId == BSC_ID) return BSC_NAME;
        else if (chainId == FANTOM_ID) return FANTOM_NAME;
        else if (chainId == AVALANCHE_ID) return AVALANCHE_NAME;
        else revert('AXELAR_UNKNOWN_CHAIN_ID');
    }
}

