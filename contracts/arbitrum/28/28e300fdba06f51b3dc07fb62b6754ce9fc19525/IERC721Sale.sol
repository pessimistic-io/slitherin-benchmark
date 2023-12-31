// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

interface IERC721SaleFunctions {

    struct SaleDetails {
        uint256 supplyCap; // 0 supply cap indicates unlimited supply
        uint256 cost;
        address paymentToken; // ERC20 token address for payment. address(0) indicated payment in ETH.
        uint64 startTime;
        uint64 endTime; // 0 end time indicates sale inactive
        bytes32 merkleRoot; // Root of allowed addresses
    }

    /**
     * Mint tokens.
     * @param to Address to mint tokens to.
     * @param amount Amount of tokens to mint.
     * @param proof Merkle proof for allowlist minting.
     * @notice Sale must be active for all tokens.
     * @dev An empty proof is supplied when no proof is required.
     */
    function mint(address to, uint256 amount, bytes32[] memory proof) external payable;

    /**
     * Set the sale details.
     * @param supplyCap The maximum number of tokens that can be minted. 0 indicates unlimited supply.
     * @param cost The amount of payment tokens to accept for each token minted.
     * @param paymentToken The ERC20 token address to accept payment in. address(0) indicates ETH.
     * @param startTime The start time of the sale. Tokens cannot be minted before this time.
     * @param endTime The end time of the sale. Tokens cannot be minted after this time.
     * @param merkleRoot The merkle root for allowlist minting.
     */
    function setSaleDetails(
        uint256 supplyCap,
        uint256 cost,
        address paymentToken,
        uint64 startTime,
        uint64 endTime,
        bytes32 merkleRoot
    ) external;

    /**
     * Get sale details.
     * @return Sale details.
     */
    function saleDetails() external view returns (SaleDetails memory);

    /**
     * Set name and symbol of token.
     * @param tokenName Name of token.
     * @param tokenSymbol Symbol of token.
     */
    function setNameAndSymbol(string memory tokenName, string memory tokenSymbol) external;
}

interface IERC721SaleSignals {
    event SaleDetailsUpdated(uint256 supplyCap, uint256 cost, address paymentToken, uint64 startTime, uint64 endTime, bytes32 merkleRoot);

    /**
     * Contract already initialized.
     */
    error InvalidInitialization();

    /**
     * Sale is not active.
     */
    error SaleInactive();

    /**
     * Insufficient supply.
     * @param currentSupply Current supply.
     * @param amount Amount to mint.
     * @param maxSupply Maximum supply.
     */
    error InsufficientSupply(uint256 currentSupply, uint256 amount, uint256 maxSupply);

    /**
     * Insufficient tokens for payment.
     * @param expected Expected amount of tokens.
     * @param actual Actual amount of tokens.
     */
    error InsufficientPayment(uint256 expected, uint256 actual);
}

interface IERC721Sale is IERC721SaleFunctions, IERC721SaleSignals {}

