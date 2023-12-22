// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Strings} from "./Strings.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import {Ownable} from "./Ownable.sol";
import {Initializable} from "./Initializable.sol";
import {IMetadataRouter} from "./IMetadataRouter.sol";
import {MetadataRouterStorage} from "./MetadataRouterStorage.sol";

/// @title GroupOS MetadataRouter Contract
/// @notice This contract implements a metadata routing mechanism that allows for dynamic configuration
/// of URIs associated with different routes and contract addresses. It enables fetching metadata
/// URIs based on routes and contract addresses, providing flexibility for managing metadata for
/// various contracts and use cases.
contract MetadataRouter is Initializable, Ownable, UUPSUpgradeable, IMetadataRouter {
    using Strings for uint256;

    /*====================
        INITIALIZATION
    ====================*/

    constructor() Initializable() {}

    /// @dev Initialize the contract with ownership information.
    /// @param _owner The address of the contract owner.
    /// @notice The contract owner will have exclusive rights to manage metadata routes and URIs.
    function initialize(address _owner) external initializer {
        _transferOwnership(_owner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /*===========
        VIEWS
    ===========*/

    /// @inheritdoc IMetadataRouter
    function contractURI() external view returns (string memory uri) {
        return _getContractRouteURI("contract", address(this));
    }

    /// @inheritdoc IMetadataRouter
    function baseURI(string memory route, address contractAddress) public view returns (string memory uri) {
        MetadataRouterStorage.Layout storage layout = MetadataRouterStorage.layout();
        uri = layout.contractRouteURI[route][contractAddress];
        if (bytes(uri).length == 0) {
            uri = layout.routeURI[route];
            if (bytes(uri).length == 0) {
                uri = layout.defaultURI;
            }
        }
        return uri;
    }

    /// @inheritdoc IMetadataRouter
    function defaultURI() external view returns (string memory) {
        return MetadataRouterStorage.layout().defaultURI;
    }

    /// @inheritdoc IMetadataRouter
    function routeURI(string memory route) external view returns (string memory) {
        return MetadataRouterStorage.layout().routeURI[route];
    }

    /// @inheritdoc IMetadataRouter
    function contractRouteURI(string memory route, address contractAddress) external view returns (string memory) {
        return MetadataRouterStorage.layout().contractRouteURI[route][contractAddress];
    }

    function _getContractRouteURI(string memory route, address contractAddress) internal view returns (string memory) {
        return string(
            abi.encodePacked(
                baseURI(route, contractAddress),
                "?chainId=",
                Strings.toString(block.chainid),
                "&contractAddress=",
                Strings.toHexString(uint160(contractAddress), 20)
            )
        );
    }

    /*====================
        CORE UTILITIES
    ====================*/

    /// @inheritdoc IMetadataRouter
    function setDefaultURI(string memory uri) external onlyOwner {
        MetadataRouterStorage.Layout storage layout = MetadataRouterStorage.layout();
        layout.defaultURI = uri;
        emit DefaultURIUpdated(uri);
    }

    /// @inheritdoc IMetadataRouter
    function setRouteURI(string memory route, string memory uri) external onlyOwner {
        MetadataRouterStorage.Layout storage layout = MetadataRouterStorage.layout();
        layout.routeURI[route] = uri;
        emit RouteURIUpdated(route, uri);
    }

    /// @inheritdoc IMetadataRouter
    function setContractRouteURI(string memory route, string memory uri, address contractAddress) external onlyOwner {
        MetadataRouterStorage.Layout storage layout = MetadataRouterStorage.layout();
        layout.contractRouteURI[route][contractAddress] = uri;
        emit ContractRouteURIUpdated(route, uri, contractAddress);
    }

    /*============
        ROUTES
    ============*/

    /// @inheritdoc IMetadataRouter
    function uriOf(string memory route, address contract_) public view returns (string memory) {
        return _getContractRouteURI(route, contract_);
    }

    /// @inheritdoc IMetadataRouter
    function uriOf(string memory route, address contract_, string memory appendData)
        public
        view
        returns (string memory)
    {
        return string(abi.encodePacked(_getContractRouteURI(route, contract_), appendData));
    }

    /// @inheritdoc IMetadataRouter
    function tokenURI(address collection, uint256 tokenId) public view returns (string memory) {
        return
            string(abi.encodePacked(_getContractRouteURI("token", collection), "&tokenId=", Strings.toString(tokenId)));
    }
}

