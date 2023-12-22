// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.20;

import "./ShadowFactory.sol";
import "./IPool.sol";
import "./ITokenDescriptor.sol";

/// @title A single ERC-1155 token shared by all Derivable pools
/// @author Derivable Labs
/// @notice An ShadowFactory and ERC1155-Maturity is used by all Derivable pools
///         for their derivative tokens, but also open to any EOA or contract by
///         rule: any EOA or contract of <address>, can mint and burn all its
///         ids that end with <address>.
contract Token is ShadowFactory {
    // Immutables
    address internal immutable UTR;
    // Storages
    address internal s_descriptor;
    address internal s_descriptorSetter;

    modifier onlyItsPool(uint256 id) {
        require(msg.sender == address(uint160(id)), "UNAUTHORIZED_MINT_BURN");
        _;
    }

    modifier onlyDescriptorSetter() {
        require(msg.sender == s_descriptorSetter, "UNAUTHORIZED");
        _;
    }

    /// @param utr The trusted UTR contract that will have unlimited approval,
    ///        can be zero to disable trusted UTR
    /// @param descriptorSetter The authorized descriptor setter,
    ///        can be zero to disable the descriptor changing
    /// @param descriptor The initial token descriptor, can be zero
    constructor(
        address utr,
        address descriptorSetter,
        address descriptor
    ) ShadowFactory("") {
        UTR = utr;
        s_descriptor = descriptor;
        s_descriptorSetter = descriptorSetter;
    }

    /// mint token with a maturity time
    /// @notice each id can only be minted by its pool contract
    /// @param to token recipient address
    /// @param id token id
    /// @param amount token amount
    /// @param maturity token maturity time, must be >= block.timestamp
    /// @param data optional payload data
    function mint(
        address to,
        uint256 id,
        uint256 amount,
        uint32 maturity,
        bytes memory data
    ) external virtual onlyItsPool(id) {
        super._mint(to, id, amount, maturity, data);
    }

    /// burn the token
    /// @notice each id can only be burnt by its pool contract
    /// @param from address to burn from
    /// @param id token id
    /// @param amount token amount
    function burn(
        address from,
        uint256 id,
        uint256 amount
    ) external virtual onlyItsPool(id) {
        super._burn(from, id, amount);
    }

    /// self-explanatory
    function name() external pure returns (string memory) {
        return "Derivable Position";
    }

    /// self-explanatory
    function symbol() external pure returns (string memory) {
        return "DERIVABLE-POS";
    }

    /// self-explanatory
    function setDescriptor(address descriptor) public onlyDescriptorSetter {
        s_descriptor = descriptor;
    }

    /// self-explanatory
    function setDescriptorSetter(address setter) public onlyDescriptorSetter {
        s_descriptorSetter = setter;
    }

    /// get the name for each shadow token
    function getShadowName(
        uint256 id
    ) public view virtual override returns (string memory) {
        return ITokenDescriptor(s_descriptor).getName(id);
    }

    /// get the symbol for each shadow token
    function getShadowSymbol(
        uint256 id
    ) public view virtual override returns (string memory) {
        return ITokenDescriptor(s_descriptor).getSymbol(id);
    }

    /// get the decimals for each shadow token
    function getShadowDecimals(
        uint256 id
    ) public view virtual override returns (uint8) {
        return ITokenDescriptor(s_descriptor).getDecimals(id);
    }

    /**
     * Generate URI by id.
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        return ITokenDescriptor(s_descriptor).constructMetadata(tokenId);
    }

    /**
     * @dev See {IERC1155-isApprovedForAll}.
     */
    function isApprovedForAll(
        address account,
        address operator
    ) public view virtual override(ERC1155Maturity, IERC1155) returns (bool) {
        return operator == UTR || super.isApprovedForAll(account, operator);
    }
}

