// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0 <0.9.0;

import "./ERC20.sol";
import {ILayerr20} from "./ILayerr20.sol";
import {ILayerrRenderer} from "./ILayerrRenderer.sol";
import {LayerrToken} from "./LayerrToken.sol";

/**
 * @title Layerr20
 * @author 0xth0mas (Layerr)
 * @notice Layerr20 is an ERC20 contract built for the Layerr platform using
 *         the Solady ERC20 implementation.
 */
contract Layerr20 is ERC20, ILayerr20, LayerrToken {

    /** METADATA FUNCTIONS */

    /**
     * @notice Returns the URI for the contract metadata
     * @return contractURI location of the contract metadata
     */
    function contractURI() public view returns (string memory) {
        return ILayerrRenderer(_getRenderer()).contractURI(address(this));
    }

    /**
     * @inheritdoc LayerrToken
     */
    function name() public view virtual override(LayerrToken, ERC20) returns (string memory) {
        return LayerrToken.name();
    }

    /**
     * @inheritdoc LayerrToken
     */
    function symbol() public view virtual override(LayerrToken, ERC20) returns (string memory) {
        return LayerrToken.symbol();
    }

    /** MINT FUNCTIONS */

    /**
     * @inheritdoc ILayerr20
     */
    function mint(address, address to, uint256 amount) external onlyMinter {
        _mint(to, amount);
    }

    /**
     * @inheritdoc ILayerr20
     */
    function burn(address from, uint256 amount) external {
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
    }

    /**
     * @inheritdoc ILayerr20
     */
    function totalSupply() public view override(ERC20, ILayerr20) returns (uint256) {
        return ERC20.totalSupply();
    }

    /**
     * @inheritdoc ILayerr20
     */
    function totalMintedTokenAndMinter(address minter) external view returns(uint256 totalMinted, uint256 minterMinted) {
        totalMinted = _totalMinted();
        minterMinted = _numberMinted(minter);
    }

    /** OWNER FUNCTIONS */

    /**
     * @inheritdoc ILayerr20
     */
    function airdrop(address[] calldata recipients, uint256[] calldata amounts) external onlyOwner {
        if(recipients.length != amounts.length) { revert ArrayLengthMismatch(); }

        for(uint256 index = 0;index < recipients.length;) {
            uint256 amount = amounts[index];
            _mint(recipients[index], amount);
            unchecked { ++index; }
        }
    }

    /** ERC165 */

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(LayerrToken) returns (bool) {
        return
            interfaceId == type(ILayerr20).interfaceId ||
            LayerrToken.supportsInterface(interfaceId);
    }
}

