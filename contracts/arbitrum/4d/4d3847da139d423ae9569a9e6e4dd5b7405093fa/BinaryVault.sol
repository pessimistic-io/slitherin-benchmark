// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import {IDiamondCut} from "./IDiamondCut.sol";
import {IDiamondLoupe} from "./IDiamondLoupe.sol";
import {IBinaryVaultPluginImpl} from "./IBinaryVaultPluginImpl.sol";
import {Ownable} from "./Ownable.sol";
import {Address} from "./Address.sol";

library BinaryVaultStorage {
    struct Layout {
        mapping(bytes4 => bool) supportedInterfaces;
        mapping(bytes4 => address) pluginSelector;
        address[] pluginImpls; // first for delegation, others for rewards
    }

    bytes32 internal constant STORAGE_SLOT =
        keccak256("balancecapital.ryze.storage.BinaryVault");

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}

/// @notice Singleton pattern for Ryze Platform, can run multiple markets on same underlying asset
/// @author https://balance.capital
contract BinaryVault is IDiamondCut, IDiamondLoupe, Ownable {
    // Find facet for function that is called and execute the
    // function if a facet is found and return any value.
    fallback() external payable {
        // get facet from function selector
        address facet = BinaryVaultStorage.layout().pluginSelector[msg.sig];
        require(facet != address(0));
        // Execute external function from facet using delegatecall and return any value.
        assembly {
            // copy function selector and any arguments
            calldatacopy(0, 0, calldatasize())
            // execute function call using the facet
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            // get any return value
            returndatacopy(0, 0, returndatasize())
            // return any return value or error back to the caller
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    function facets() external view returns (Facet[] memory facets_) {
        BinaryVaultStorage.Layout storage l = BinaryVaultStorage.layout();
        uint256 length = l.pluginImpls.length;
        facets_ = new Facet[](length);
        for (uint256 i; i < length; i++) {
            address plugin = l.pluginImpls[i];
            (bytes4[] memory selectors, ) = IBinaryVaultPluginImpl(plugin)
                .pluginMetadata();
            facets_[i] = Facet(plugin, selectors);
        }
    }

    function facetFunctionSelectors(address _facet)
        external
        view
        returns (bytes4[] memory facetFunctionSelectors_)
    {
        BinaryVaultStorage.Layout storage l = BinaryVaultStorage.layout();
        uint256 length = l.pluginImpls.length;
        for (uint256 i; i < length; i++) {
            if (l.pluginImpls[i] == _facet) {
                (facetFunctionSelectors_, ) = IBinaryVaultPluginImpl(_facet)
                    .pluginMetadata();
                break;
            }
        }
    }

    function facetAddresses()
        external
        view
        returns (address[] memory facetAddresses_)
    {
        facetAddresses_ = BinaryVaultStorage.layout().pluginImpls;
    }

    function facetAddress(bytes4 _functionSelector)
        external
        view
        returns (address facetAddress_)
    {
        facetAddress_ = BinaryVaultStorage.layout().pluginSelector[
            _functionSelector
        ];
    }

    /// @notice Add/replace/remove any number of functions and optionally execute
    ///         a function with delegatecall
    /// @param _diamondCut Contains the facet addresses and function selectors
    /// @param _init The address of the contract or facet to execute _calldata
    /// @param _calldata A function call, including function selector and arguments
    ///                  _calldata is executed with delegatecall on _init
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external onlyOwner {
        BinaryVaultStorage.Layout storage s = BinaryVaultStorage.layout();

        for (uint256 i = 0; i < _diamondCut.length; i++) {
            FacetCut memory cut = _diamondCut[i];
            address facet = cut.facetAddress;
            (, bytes4 interfaceId) = IBinaryVaultPluginImpl(facet)
                .pluginMetadata();

            require(facet != address(0), "Diamond: Invalid facet address");
            require(Address.isContract(facet), "Diamond: Facet has no code");

            if (cut.action == FacetCutAction.Add) {
                s.pluginImpls.push(facet);
                s.supportedInterfaces[interfaceId] = true;

                for (uint256 j = 0; j < cut.functionSelectors.length; j++) {
                    bytes4 selector = cut.functionSelectors[j];

                    require(
                        s.pluginSelector[selector] == address(0),
                        "Diamond: Function selector already added"
                    );

                    s.pluginSelector[selector] = facet;
                }
            } else if (cut.action == FacetCutAction.Replace) {
                s.pluginImpls.push(facet);
                s.supportedInterfaces[interfaceId] = true;

                for (uint256 j = 0; j < cut.functionSelectors.length; j++) {
                    bytes4 selector = cut.functionSelectors[j];

                    s.pluginSelector[selector] = facet;
                }
            } else {
                for (uint256 j = 0; j < cut.functionSelectors.length; j++) {
                    bytes4 selector = cut.functionSelectors[j];

                    delete s.pluginSelector[selector];
                }
            }
        }

        if (_init != address(0)) {
            (bool success, bytes memory result) = _init.delegatecall(_calldata);

            if (!success) {
                if (result.length == 0)
                    revert("DelegateCallHelper: revert with no reason");
                assembly {
                    let result_len := mload(result)
                    revert(add(32, result), result_len)
                }
            }
        }

        emit DiamondCut(_diamondCut, _init, _calldata);
    }

    function supportsInterface(bytes4 interfaceID)
        external
        view
        returns (bool supported)
    {
        supported = BinaryVaultStorage.layout().supportedInterfaces[
            interfaceID
        ];
    }
}

