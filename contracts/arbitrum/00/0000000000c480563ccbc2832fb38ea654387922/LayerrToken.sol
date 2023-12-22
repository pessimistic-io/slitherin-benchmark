// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import {AddressValue, StringValue} from "./StorageTypes.sol";
import {LAYERRTOKEN_NAME_SLOT, LAYERRTOKEN_SYMBOL_SLOT, LAYERRTOKEN_RENDERER_SLOT} from "./LayerrStorage.sol";
import {LayerrOwnable} from "./LayerrOwnable.sol";
import {ILayerrToken} from "./ILayerrToken.sol";
import {ILayerrMinter} from "./ILayerrMinter.sol";
import {ERC2981} from "./ERC2981.sol";

/**
 * @title LayerrToken
 * @author 0xth0mas (Layerr)
 * @notice LayerrToken contains the general purpose token contract functions for interacting
 *         with the Layerr platform.
 */
contract LayerrToken is ILayerrToken, LayerrOwnable, ERC2981 {

    /// @dev mapping of allowed mint extensions
    mapping(address => bool) public mintingExtensions;

    modifier onlyMinter() {
        if (!mintingExtensions[msg.sender]) {
            revert NotValidMintingExtension();
        }
        _;
    }

    /**
     * @inheritdoc ILayerrToken
     */
    function name() public virtual view returns(string memory _name) {
        StringValue storage nameValue;
        /// @solidity memory-safe-assembly
        assembly {
            nameValue.slot := LAYERRTOKEN_NAME_SLOT
        }
        _name = nameValue.value;
    }

    /**
     * @inheritdoc ILayerrToken
     */
    function symbol() public virtual view returns(string memory _symbol) {
        StringValue storage symbolValue;
        /// @solidity memory-safe-assembly
        assembly {
            symbolValue.slot := LAYERRTOKEN_SYMBOL_SLOT
        }
        _symbol = symbolValue.value;
    }

    /**
     * @inheritdoc ILayerrToken
     */
    function renderer() external view returns(address _renderer) {
        _renderer = _getRenderer();
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(LayerrOwnable, ERC2981) returns (bool) {
        return interfaceId == type(ILayerrToken).interfaceId ||
            ERC2981.supportsInterface(interfaceId) ||
            LayerrOwnable.supportsInterface(interfaceId);
    }

    /* OWNER FUNCTIONS */

    /**
     * @inheritdoc ILayerrToken
     */
    function setRenderer(address _renderer) external onlyOwner {
        _setRenderer(_renderer);

        emit RendererUpdated(_renderer);
    }

    /**
     * @inheritdoc ILayerrToken
     */
    function setMintExtension(
        address _extension,
        bool _allowed
    ) external onlyOwner {
        mintingExtensions[_extension] = _allowed;

        emit MintExtensionUpdated(_extension, _allowed);
    }

    /**
     * @inheritdoc ILayerrToken
     */
    function setContractAllowedSigner(
        address _extension,
        address _signer,
        bool _allowed
    ) external onlyOwner {
        ILayerrMinter(_extension).setContractAllowedSigner(_signer, _allowed);
    }

    /**
     * @inheritdoc ILayerrToken
     */
    function setContractAllowedOracle(
        address _extension,
        address _oracle,
        bool _allowed
    ) external onlyOwner {
        ILayerrMinter(_extension).setContractAllowedOracle(_oracle, _allowed);
    }

    /**
     * @inheritdoc ILayerrToken
     */
    function setSignatureValidity(
        address _extension,
        bytes32[] calldata signatureDigests,
        bool invalid
    ) external onlyOwner {
        ILayerrMinter(_extension).setSignatureValidity(signatureDigests, invalid);
    }

    /**
     * @inheritdoc ILayerrToken
     */
    function setRoyalty(
        uint96 pct,
        address royaltyReciever
    ) external onlyOwner {
        _setDefaultRoyalty(royaltyReciever, pct);
    }

    /**
     * @inheritdoc ILayerrToken
     */
    function editContract(
        string calldata _name,
        string calldata _symbol
    ) external onlyOwner {
        _setName(_name);
        _setSymbol(_symbol);
    }

    /**
     * @notice Called during a proxy deployment to emit the LayerrContractDeployed event
     */
    function initialize() external onlyOwner {
        emit LayerrContractDeployed();
    }

    /**
     * @notice Called to withdraw any funds that may be sent to the contract
     */
    function withdraw() external onlyOwner {
        (bool sent, ) = payable(_getOwner()).call{value: address(this).balance}("");
        if (!sent) {
            revert WithdrawFailed();
        }
    }

    /**
     *  INTERNAL FUNCTIONS
     */

    /**
     * @notice Internal function to set the renderer address in a custom storage slot location
     * @param _renderer address of the renderer to set
     */
    function _setRenderer(address _renderer) internal {
        AddressValue storage rendererValue;
        /// @solidity memory-safe-assembly
        assembly {
            rendererValue.slot := LAYERRTOKEN_RENDERER_SLOT
        }
        rendererValue.value = _renderer;
    }

    /**
     * @notice Internal function to get the renderer address from a custom storage slot location
     * @return _renderer address of the renderer
     */
    function _getRenderer() internal view returns(address _renderer) {
        AddressValue storage rendererValue;
        /// @solidity memory-safe-assembly
        assembly {
            rendererValue.slot := LAYERRTOKEN_RENDERER_SLOT
        }
        _renderer = rendererValue.value;
    }

    /**
     * @notice Internal function to set the token contract name in a custom storage slot location
     * @param _name name for the token contract
     */
    function _setName(string calldata _name) internal {
        StringValue storage nameValue;
        /// @solidity memory-safe-assembly
        assembly {
            nameValue.slot := LAYERRTOKEN_NAME_SLOT
        }
        nameValue.value = _name;
    }

    /**
     * @notice Internal function to set the token contract symbol in a custom storage slot location
     * @param _symbol symbol for the token contract
     */
    function _setSymbol(string calldata _symbol) internal {
        StringValue storage symbolValue;
        /// @solidity memory-safe-assembly
        assembly {
            symbolValue.slot := LAYERRTOKEN_SYMBOL_SLOT
        }
        symbolValue.value = _symbol;
    }
}
