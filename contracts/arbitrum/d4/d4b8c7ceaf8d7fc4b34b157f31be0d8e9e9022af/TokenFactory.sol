// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.13;

import {ERC1967Proxy} from "./ERC1967Proxy.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import {IERC20} from "./IERC20.sol";
import {IERC721} from "./IERC721.sol";
import {IERC1155} from "./IERC1155.sol";
import {Ownable} from "./Ownable.sol";
import {Initializable} from "./Initializable.sol";
import {IERC721Rails} from "./IERC721Rails.sol";
import {IERC20Rails} from "./IERC20Rails.sol";
import {IERC1155Rails} from "./IERC1155Rails.sol";
import {ITokenFactory} from "./ITokenFactory.sol";
import {TokenFactoryStorage} from "./TokenFactoryStorage.sol";

contract TokenFactory is Initializable, Ownable, UUPSUpgradeable, ITokenFactory {
    /*============
        SET UP
    ============*/

    constructor() Initializable() {}

    /// @inheritdoc ITokenFactory
    function initialize(address owner_, address erc20Impl_, address erc721Impl_, address erc1155Impl_)
        external
        initializer
    {
        _transferOwnership(owner_);
        _addImplementation(
            TokenFactoryStorage.TokenImpl({
                implementation: erc20Impl_,
                tokenStandard: TokenFactoryStorage.TokenStandard.ERC20
            })
        );
        _addImplementation(
            TokenFactoryStorage.TokenImpl({
                implementation: erc721Impl_,
                tokenStandard: TokenFactoryStorage.TokenStandard.ERC721
            })
        );
        _addImplementation(
            TokenFactoryStorage.TokenImpl({
                implementation: erc1155Impl_,
                tokenStandard: TokenFactoryStorage.TokenStandard.ERC1155
            })
        );
    }

    /*============
        CREATE
    ============*/

    /// @inheritdoc ITokenFactory
    function createERC20(
        address payable implementation,
        bytes32 inputSalt,
        address owner,
        string memory name,
        string memory symbol,
        bytes calldata initData
    ) public returns (address payable token) {
        _checkIsApprovedImplementation(implementation, TokenFactoryStorage.TokenStandard.ERC20);

        bytes32 deploymentSalt = keccak256(abi.encode(inputSalt, owner, name, symbol, initData));
        token = payable(address(new ERC1967Proxy{salt: deploymentSalt}(implementation, bytes(""))));
        emit ERC20Created(token);

        IERC20Rails(token).initialize(owner, name, symbol, initData);
    }

    /// @inheritdoc ITokenFactory
    function createERC721(
        address payable implementation,
        bytes32 inputSalt,
        address owner,
        string memory name,
        string memory symbol,
        bytes calldata initData
    ) public returns (address payable token) {
        _checkIsApprovedImplementation(implementation, TokenFactoryStorage.TokenStandard.ERC721);

        bytes32 deploymentSalt = keccak256(abi.encode(inputSalt, owner, name, symbol, initData));
        token = payable(address(new ERC1967Proxy{salt: deploymentSalt}(implementation, bytes(""))));
        emit ERC721Created(token);

        IERC721Rails(token).initialize(owner, name, symbol, initData);
    }

    /// @inheritdoc ITokenFactory
    function createERC1155(
        address payable implementation,
        bytes32 inputSalt,
        address owner,
        string memory name,
        string memory symbol,
        bytes calldata initData
    ) public returns (address payable token) {
        _checkIsApprovedImplementation(implementation, TokenFactoryStorage.TokenStandard.ERC1155);

        bytes32 deploymentSalt = keccak256(abi.encode(inputSalt, owner, name, symbol, initData));
        token = payable(address(new ERC1967Proxy{salt: deploymentSalt}(implementation, bytes(""))));
        emit ERC1155Created(token);

        IERC1155Rails(token).initialize(owner, name, symbol, initData);
    }

    /*===========
        VIEWS
    ===========*/

    function getApprovedImplementations() public view returns (TokenFactoryStorage.TokenImpl[] memory allImpls) {
        allImpls = TokenFactoryStorage.layout().tokenImplementations;
    }

    function getApprovedImplementations(TokenFactoryStorage.TokenStandard standard)
        public
        view
        returns (TokenFactoryStorage.TokenImpl[] memory)
    {
        TokenFactoryStorage.Layout storage layout = TokenFactoryStorage.layout();
        TokenFactoryStorage.TokenImpl[] memory allImpls = getApprovedImplementations();

        // Solidity cannot elegantly handle resizing dynamic arrays in memory so loop is performed twice
        uint256 lenCounter;
        for (uint256 i; i < allImpls.length; ++i) {
            if (allImpls[i].tokenStandard == standard) {
                ++lenCounter;
            }
        }

        TokenFactoryStorage.TokenImpl[] memory filteredImpls = new TokenFactoryStorage.TokenImpl[](lenCounter);
        uint256 k;
        for (uint256 j; j < allImpls.length; ++j) {
            if (allImpls[j].tokenStandard == standard) {
                filteredImpls[k] = allImpls[j];
                ++k;
            }
        }

        return filteredImpls;
    }

    /*=============
        SETTERS
    =============*/

    /// @inheritdoc ITokenFactory
    function addImplementation(TokenFactoryStorage.TokenImpl memory tokenImpl) public onlyOwner {
        _addImplementation(tokenImpl);
    }

    /// @inheritdoc ITokenFactory
    function removeImplementation(TokenFactoryStorage.TokenImpl memory tokenImpl) public onlyOwner {
        _removeImplementation(tokenImpl);
    }

    /*===============
        INTERNALS
    ===============*/

    function _checkIsApprovedImplementation(address _implementation, TokenFactoryStorage.TokenStandard _standard)
        internal
    {
        TokenFactoryStorage.TokenImpl[] memory filteredImpls = getApprovedImplementations(_standard);
        for (uint256 i; i < filteredImpls.length; ++i) {
            // if match is found, exit without reverting
            if (filteredImpls[i].implementation == _implementation) return;
        }

        revert InvalidImplementation();
    }

    function _addImplementation(TokenFactoryStorage.TokenImpl memory _tokenImpl) internal {
        TokenFactoryStorage.Layout storage layout = TokenFactoryStorage.layout();
        layout.tokenImplementations.push(_tokenImpl);
    }

    function _removeImplementation(TokenFactoryStorage.TokenImpl memory _tokenImpl) internal {
        // instantiate memory copies to minimize gas cost
        TokenFactoryStorage.TokenImpl[] memory allImpls = getApprovedImplementations();

        unchecked {
            uint256 length = allImpls.length;
            for (uint256 i; i < length; ++i) {
                // find match if it exists
                if (allImpls[i].implementation != _tokenImpl.implementation) continue;

                // if match found && it is not final index, copy final member deeper into array
                TokenFactoryStorage.Layout storage layout = TokenFactoryStorage.layout();
                if (i != length - 1) {
                    // only write to storage once match is found
                    layout.tokenImplementations[i] = allImpls[length - 1];
                }

                // remove final index of storage array after copying its data deeper into array
                delete layout.tokenImplementations[length - 1];
            }
        }
    }

    /*===============
        OVERRIDES
    ===============*/

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

