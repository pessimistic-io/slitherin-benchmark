// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

import {ERC721Sale} from "./ERC721Sale.sol";
import {IERC721SaleFactory} from "./IERC721SaleFactory.sol";
import {SequenceProxyFactory} from "./SequenceProxyFactory.sol";

/**
 * Deployer of ERC-721 Sale proxies.
 */
contract ERC721SaleFactory is IERC721SaleFactory, SequenceProxyFactory {
    /**
     * Creates an ERC-721 Sale Factory.
     * @param factoryOwner The owner of the ERC-721 Sale Factory
     */
    constructor(address factoryOwner) {
        ERC721Sale impl = new ERC721Sale();
        SequenceProxyFactory._initialize(address(impl), factoryOwner);
    }

    /**
     * Creates an ERC-721 Sale for given token contract
     * @param proxyOwner The owner of the ERC-721 Sale proxy
     * @param tokenOwner The owner of the ERC-721 Sale implementation
     * @param name The name of the ERC-721 Sale token
     * @param symbol The symbol of the ERC-721 Sale token
     * @param baseURI The base URI of the ERC-721 Sale token
     * @param royaltyReceiver Address of who should be sent the royalty payment
     * @param royaltyFeeNumerator The royalty fee numerator in basis points (e.g. 15% would be 1500)
     * @return proxyAddr The address of the ERC-721 Sale Proxy
     * @dev As `proxyOwner` owns the proxy, it will be unable to call the ERC-721 Sale functions.
     */
    function deploy(
        address proxyOwner,
        address tokenOwner,
        string memory name,
        string memory symbol,
        string memory baseURI,
        address royaltyReceiver,
        uint96 royaltyFeeNumerator
    )
        external
        returns (address proxyAddr)
    {
        bytes32 salt =
            keccak256(abi.encodePacked(tokenOwner, name, symbol, baseURI, royaltyReceiver, royaltyFeeNumerator));
        proxyAddr = _createProxy(salt, proxyOwner, "");
        ERC721Sale(proxyAddr).initialize(tokenOwner, name, symbol, baseURI, royaltyReceiver, royaltyFeeNumerator);
        emit ERC721SaleDeployed(proxyAddr);
        return proxyAddr;
    }
}

